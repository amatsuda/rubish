# frozen_string_literal: true

module Rubish
  # Shared word-segment parser used by both Codegen (compile time) and
  # Expansion (runtime). A shell word token may be a sequence of adjacent
  # quoted and unquoted segments, eg. unquoted'single'"double". This module
  # provides the parsing logic once so neither side has to duplicate it.
  module WordSegments
    # Yields (type, content) for each segment of str.
    # type is one of: :single, :double, :ansi_c, :bare
    # content is the inner text (quotes already stripped).
    # $(...), ${...}, and `...` can contain a literal " that must not be read as
    # a double-quote boundary. When one begins at str[i], return the index just
    # past it, else nil.
    def self.skip_expansion(str, i)
      if str[i] == '$' && (str[i + 1] == '(' || str[i + 1] == '{')
        open = str[i + 1]
        close = open == '(' ? ')' : '}'
        depth = 1
        j = i + 2
        while j < str.length && depth > 0
          depth += 1 if str[j] == open
          depth -= 1 if str[j] == close
          j += 1
        end
        j
      elsif str[i] == '`'
        j = i + 1
        j += (str[j] == '\\' ? 2 : 1) while j < str.length && str[j] != '`'
        j < str.length ? j + 1 : j
      end
    end

    def self.each_segment(str)
      i = 0
      while i < str.length
        if str[i, 2] == "$'"
          j = str.index("'", i + 2) || str.length
          yield :ansi_c, str[i + 2...j]
          i = j < str.length ? j + 1 : str.length
        elsif str[i] == "'"
          j = str.index("'", i + 1) || str.length
          yield :single, str[i + 1...j]
          i = j < str.length ? j + 1 : str.length
        elsif str[i] == '"'
          j = i + 1
          while j < str.length && str[j] != '"'
            if str[j] == '\\'
              j += 2
            elsif (skip = skip_expansion(str, j))
              j = skip
            else
              j += 1
            end
          end
          yield :double, str[i + 1...j]
          i = j < str.length ? j + 1 : str.length
        else
          j = i
          while j < str.length
            c = str[j]
            if c == '$' && j + 1 < str.length
              nc = str[j + 1]
              if nc == "'"
                break
              elsif nc == '(' || nc == '{'
                open_c = nc; close_c = nc == '(' ? ')' : '}'; depth = 1; j += 2
                while j < str.length && depth > 0
                  depth += 1 if str[j] == open_c
                  depth -= 1 if str[j] == close_c
                  j += 1
                end
              else
                j += 1
              end
            elsif c == '`'
              j += 1
              while j < str.length
                break if str[j] == '`'
                j += 2 if str[j] == '\\'
                j += 1
              end
              j += 1 if j < str.length
            elsif c == "'" || c == '"'
              break
            else
              j += 1
            end
          end
          yield :bare, str[i...j]
          i = j
        end
      end
    end

    # Returns true when str contains more than one segment (ie. it is an
    # adjacent/mixed quoted word rather than a plain quoted or bare token).
    def self.multi_segment?(str)
      return false unless str.match?(/['"]/)
      return false if str.start_with?("$'") && str.end_with?("'")

      if str.start_with?("'")
        close = str.index("'", 1)
        return close ? close != str.length - 1 : false
      end

      if str.start_with?('"')
        i = 1
        while i < str.length
          if str[i] == '\\'
            i += 2
          elsif (skip = skip_expansion(str, i))
            i = skip
          elsif str[i] == '"'
            return i != str.length - 1
          else
            i += 1
          end
        end
        return false
      end

      # $(...), ${...}, $"..." and `...` are single tokens, not multi-segment words
      return false if str.start_with?('$(', '${', '$"', '`')

      # bare word — scan for top-level quote boundaries, skipping $(, ${, ` blocks
      j = 0
      while j < str.length
        c = str[j]
        if c == '$' && j + 1 < str.length
          nc = str[j + 1]
          if nc == "'"
            return true
          elsif nc == '(' || nc == '{'
            open_c = nc; close_c = nc == '(' ? ')' : '}'; depth = 1; j += 2
            while j < str.length && depth > 0
              depth += 1 if str[j] == open_c
              depth -= 1 if str[j] == close_c
              j += 1
            end
          else
            j += 1
          end
        elsif c == '`'
          j += 1
          while j < str.length
            break if str[j] == '`'
            j += 2 if str[j] == '\\'
            j += 1
          end
          j += 1 if j < str.length
        elsif c == "'" || c == '"'
          return true
        else
          j += 1
        end
      end
      false
    end
  end
end
