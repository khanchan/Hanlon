require "object"

module ProjectHanlon
  module Tagging
    class TagRule < ProjectHanlon::Object
      include(ProjectHanlon::Logging)

      attr_accessor :name
      attr_accessor :tag
      attr_accessor :tag_matchers
      attr_accessor :field

      def initialize(hash)
        super()
        @name = "Tag Rule: #{@uuid}"
        @tag = ""
        @field = nil
        @tag_matchers = []
        @_namespace = :tag
        @noun = "tag"

        from_hash(hash) unless hash == nil
        tag_matcher_from_hash unless hash == nil || @field
      end

      # This method is called by the engine on tagging
      # It allows us to parse the tag metaname vars and reply back with a correct tag
      def get_tag(node)
        if @field
          return sanitize_tag node.attributes_hash[@field]
        end
        sanitize_tag parse_tag_metadata_vars(node.attributes_hash)
      end

      # Remove symbols, whitespace, junk from tags
      # tags are alphanumeric mostly (with the exception of '%, =, -, _')
      def sanitize_tag(in_tag)
        in_tag.gsub(/[^\w%=\-\\+]+/,"")
      end

      # Used for parsing tag metanaming vars
      def parse_tag_metadata_vars(meta)
        begin
          return tag unless meta
          new_tag = tag
          # Direct value metaname var
          # pattern:  %V=key_name-%
          # Where 'key_name' is the key name from the metadata hash
          # directly inserts the value or nothing if nil
          direct_value = new_tag.scan(/%V=[\w ]*-%/)
          direct_value.map! do |dv|
            {
                :var => dv,
                :key_name => dv.gsub(/%V=|-%/, ""),
                :value => meta[dv.gsub(/%V=|-%/, "")]
            }
          end
          direct_value.each do
          |dv|
            dv[:value] ||= ""
            new_tag = new_tag.gsub(dv[:var].to_s,dv[:value].to_s)
          end


          # Selected value metaname var
          # pattern:  %R=selection_pattern:key_name-%
          # Where 'key_name' is the key name from the metadata hash
          # Where 'selection_pattern' is a Regex string for selecting a portion of the value from the key name in the metadata hash
          # directly inserts the value or nothing if nil
          selected_value = new_tag.scan(/%R=.+:[\w]+-%/)
          selected_value.map! do |dv|
            {
                :var => dv,
                :var_string => dv.gsub(/%R=|-%/, ""),
                :key_name => dv.gsub(/%R=|-%/, "").split(":")[1],
                :pattern => Regexp.new(dv.gsub(/%R=|-%/, "").split(":").first)
            }
          end

          selected_value.each do
          |sv|
            if sv[:pattern] && sv[:key_name]
              sv[:value] = sv[:pattern].match(meta[sv[:key_name]]).to_s
            end
            sv[:value] ||= ""
            new_tag = new_tag.gsub(sv[:var].to_s,sv[:value].to_s)
          end
        rescue => e
          logger.error "ERROR: #{e}"
          tag
        end
        new_tag
      end

      def check_tag_rule(attributes_hash)
        logger.debug "Checking tag rule"

        # if it's a value tag, the field referenced should be one of the
        # keys in the attributes_hash and the value associated with that
        # key should be a string (return false if either of these two
        # conditions are not met)
        if @field
          unless attributes_hash.keys.include?(@field)
            logger.warn "Field '#{@field}' not found in attributes hash"
            return false
          end
          is_string = attributes_hash[@field].class == String
          logger.warn "Value in matching field '#{@field}' is not a String" unless is_string
          return is_string
        end

        logger.warn "No tag matchers for tag rule" if @tag_matchers.count == 0
        return false if @tag_matchers.count == 0

        @tag_matchers.each do
        |tag_matcher|
          logger.debug "Tag Matcher key: #{tag_matcher.key}"

          # For each tag matcher we go through the attributes_hash and look for matching key and matching value

          # If key isn't found we return false
          if attributes_hash[tag_matcher.key] == nil && tag_matcher.inverse == false # we don't care if matcher is inverse
            logger.debug "Key #{tag_matcher.key} does not exist"
            return false
          end
          # If key/value doesn't match we return false
          unless tag_matcher.check_for_match(attributes_hash[tag_matcher.key])
            logger.debug "Key #{tag_matcher.key} does not match"
            return false
          end
        end

        # Otherwise we return true
        true
      end

      def add_tag_matcher(options = {})
        key = options[:key]
        value = options[:value]
        compare = options[:compare]
        inverse = options[:inverse]
        logger.debug "New tag matcher: '#{key}' #{compare} '#{value}' inverse:#{inverse.to_s}"
        if key.class == String && value.class == String
          if compare == "equal" || compare == "like"
            if inverse.to_s == "true" || inverse.to_s == "false"


              tag_matcher = ProjectHanlon::Tagging::TagMatcher.new({"@key" => key,
                                                                   "@value" => value,
                                                                   "@compare" => compare,
                                                                   "@inverse" => inverse.to_s},
                                                                  @uuid)
              if tag_matcher.class == ProjectHanlon::Tagging::TagMatcher
                logger.debug "New tag matcher added successfully"
                @tag_matchers << tag_matcher
                return tag_matcher
              end
            else
              logger.warn "Tag matcher inverse value should be 'true' or 'false': #{inverse.to_s}"
            end
          else
            logger.warn "Tag matcher compare value should be 'equal' or 'like': #{compare}"
          end
        else
          logger.warn "Tag matcher key and value classes should be String: #{key.class}, #{value.class}"
        end
        false
      end

      def remove_tag_matcher(uuid)
        tag_matcher_from_hash
        tag_matchers.delete_if {|tag_matcher| tag_matcher.uuid == uuid}
      end

      def tag_matcher_from_hash
        new_array = []
        @tag_matchers.each do
        |tag_matcher_hash|
          if tag_matcher_hash.class == Hash || tag_matcher_hash.class == BSON::OrderedHash # change this to check descendant of Hash
            new_array << ProjectHanlon::Tagging::TagMatcher.new(tag_matcher_hash, @uuid)
          else
            new_array << tag_matcher_hash
          end
        end

        @tag_matchers = new_array
      end


      # Override from_hash to convert our tag matchers if they exist
      def from_hash(hash)
        super(hash)
        new_tag_matchers_array = []
        @tag_matchers.each do
        |tag_matcher|
          if tag_matcher.class != ProjectHanlon::Tagging::TagMatcher
            new_tag_matchers_array << ProjectHanlon::Tagging::TagMatcher.new(tag_matcher, @uuid)
          else
            new_tag_matchers_array << tag_matcher
          end
        end
      end

      def to_hash
        @tag_matchers = @tag_matchers.each {|tm| tm.to_hash}
        super
      end

      def print_header
        # return a header that can be used with any of our tag
        # types (tags, value tags, or system tags)
        ["Name", "Tag/Field", "UUID", "Type"]
      end

      def print_items
        # if it's a value tag, return the values appropriate for that
        # type of tag (along with a type of 'val')
        return [@name, @field, @uuid, 'val'] if @field
        # check to see if it's a system tag or not (based on the formatting
        # used in those tags for the tag string)
        systag_parse = /^([\S]*)%V=([\S]+)-%([\S]*)$/.match(@tag)
        # if the regex matched, it's a system-defined tag, so return the
        # values appropriate for a system tag (along with a type of 'sys')
        return [@name, "#{systag_parse[1]}{#{systag_parse[2]}}#{systag_parse[3]}", 'N/A', 'sys'] if systag_parse
        # else, return the values appropriate for a regular tag (along with
        # a type of 'tag')
        [@name, @tag, @uuid, 'tag']
      end

      def print_item_header
        # if it's a value tag, return the appropriate header
        # (there's no Matcher to return)
        return ["Name", "Field", "UUID"] if @field
        # else, return the header appropriate for a regular tag
        ["Name", "Tag", "UUID", "Matcher"]
      end

      def print_item
        # if it's a value tag, return the appropriate values
        # (there are no tag matchers associated with a value tag)
        return [@name, @field, @uuid] if @field
        # else, return the values appropriate for a regular tag
        [@name, @tag, @uuid, tag_matcher_print]
      end

      def line_color
        :white_on_black
      end

      def header_color
        :red_on_black
      end

      def tag_matcher_print
        #return @tag_matchers.inspect
        if @tag_matchers.count > 0
          print_string = "\n"
          @tag_matchers.each do
          |tm|
            tm = ProjectHanlon::Tagging::TagMatcher.new(tm, @uuid) unless tm.class == ProjectHanlon::Tagging::TagMatcher
            print_string << "\t#{tm.uuid} - '#{tm.key}' (#{tm.inverse == "true" ? "NOT " : ""}#{tm.compare}) '#{tm.value}'\n"
          end
          print_string
        else
          "<none>"
        end
      end


    end
  end
end
