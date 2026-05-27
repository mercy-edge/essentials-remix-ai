# frozen_string_literal: true
#-------------------------------------------------------------------------------
# Pure Ruby JSON read/write for MKXP — no stdlib 'json' or 'yaml'.
# Objects, arrays, strings (UTF-8), numbers, true/false/null.
#-------------------------------------------------------------------------------
module MapYamlBridge
  module PureJson
    module_function

    def parse(str)
      s = str.to_s.dup
      s.force_encoding(Encoding::UTF_8) if s.respond_to?(:force_encoding)
      Parser.new(s).parse_root
    end

    def pretty_generate(obj, indent_step = 2)
      Pretty.new(indent_step).generate(obj)
    end

    class Parser
      def initialize(s)
        @s = s
        @i = 0
        @len = s.length
      end

      def parse_root
        skip_ws
        v = parse_value
        skip_ws
        raise err('trailing data after JSON') if @i < @len

        v
      end

      def skip_ws
        while @i < @len
          c = @s[@i]
          break unless c =~ /\A[ \t\r\n]\z/

          @i += 1
        end
      end

      def parse_value
        skip_ws
        c = @s[@i]
        case c
        when '{' then parse_object
        when '[' then parse_array
        when '"' then parse_string
        when 't' then expect_word('true', true)
        when 'f' then expect_word('false', false)
        when 'n' then expect_word('null', nil)
        when '-', '0'..'9' then parse_number
        else
          raise err("unexpected #{c.inspect} at #{@i}")
        end
      end

      def parse_object
        expect('{')
        skip_ws
        h = {}
        if @s[@i] == '}'
          @i += 1
          return h
        end

        loop do
          skip_ws
          raise err('expected string key') unless @s[@i] == '"'

          k = parse_string
          skip_ws
          expect(':')
          v = parse_value
          h[k] = v
          skip_ws
          case @s[@i]
          when ','
            @i += 1
          when '}'
            @i += 1
            return h
          else
            raise err('expected , or }')
          end
        end
      end

      def parse_array
        expect('[')
        skip_ws
        a = []
        if @s[@i] == ']'
          @i += 1
          return a
        end

        loop do
          a.push(parse_value)
          skip_ws
          case @s[@i]
          when ','
            @i += 1
          when ']'
            @i += 1
            return a
          else
            raise err('expected , or ]')
          end
        end
      end

      def parse_string
        expect('"')
        buf = String.new
        while @i < @len
          c = @s[@i]
          if c == '"'
            @i += 1
            return buf
          elsif c == '\\'
            @i += 1
            raise err('bad escape (eof)') if @i >= @len

            esc = @s[@i]
            @i += 1
            case esc
            when '"' then buf << '"'
            when '\\' then buf << '\\'
            when '/' then buf << '/'
            when 'b' then buf << "\b"
            when 'f' then buf << "\f"
            when 'n' then buf << "\n"
            when 'r' then buf << "\r"
            when 't' then buf << "\t"
            when 'u'
              hex = @s[@i, 4]
              raise err('bad \\u') unless hex =~ /\A[0-9a-fA-F]{4}\z/

              @i += 4
              cp = hex.hex
              buf << cp.chr(Encoding::UTF_8)
            else
              raise err("bad escape \\#{esc}")
            end
          else
            buf << c
            @i += 1
          end
        end
        raise err('unterminated string')
      end

      def parse_number
        rest = @s[@i..-1]
        m = /\A(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.match(rest)
        raise err('bad number') unless m

        raw = m[1]
        @i += raw.length
        if raw.include?('.') || raw =~ /[eE]/
          raw.to_f
        else
          raw.to_i
        end
      end

      def expect_word(word, ret)
        word.each_char do |ch|
          raise err("expected #{word}") if @s[@i] != ch

          @i += 1
        end
        ret
      end

      def expect(ch)
        raise err("expected #{ch.inspect}") if @s[@i] != ch

        @i += 1
      end

      def err(msg)
        RuntimeError.new("[MapYamlBridge::PureJson] #{msg}")
      end
    end

    class Pretty
      def initialize(indent_step)
        @n = [indent_step, 1].max
      end

      def generate(obj)
        encode(obj, 0) + "\n"
      end

      def encode(obj, depth)
        pad = ' ' * (@n * depth)
        inner_pad = ' ' * (@n * (depth + 1))
        case obj
        when Hash
          return '{}' if obj.empty?

          pairs = obj.keys.map do |k|
            "#{inner_pad}#{esc_str(k.to_s)}: #{encode_value(obj[k], depth + 1)}"
          end
          "{\n#{pairs.join(",\n")}\n#{pad}}"
        when Array
          return '[]' if obj.empty?

          elems = obj.map do |v|
            "#{inner_pad}#{encode_value(v, depth + 1)}"
          end
          "[\n#{elems.join(",\n")}\n#{pad}]"
        else
          encode_value(obj, depth)
        end
      end

      def encode_value(obj, depth)
        case obj
        when Hash, Array
          encode(obj, depth)
        when String
          esc_str(obj)
        when Integer, Float
          obj.to_s
        when true then 'true'
        when false then 'false'
        when nil then 'null'
        else
          raise RuntimeError, "[MapYamlBridge::PureJson] cannot encode #{obj.class}"
        end
      end

      def esc_str(s)
        buf = String.new
        buf << '"'
        s.each_char do |ch|
          case ch
          when '"'  then buf << '\\"'
          when '\\' then buf << '\\\\'
          when "\b" then buf << '\\b'
          when "\f" then buf << '\\f'
          when "\n" then buf << '\\n'
          when "\r" then buf << '\\r'
          when "\t" then buf << '\\t'
          else
            o = ch.ord
            buf << (o < 0x20 ? sprintf('\\u%04x', o) : ch)
          end
        end
        buf << '"'
        buf
      end
    end
  end
end
