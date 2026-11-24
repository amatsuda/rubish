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
        elsif str[i, 2] == '$"'
          # $"..." is a double-quoted string (translation has no catalogue here)
          j = i + 2
          while j < str.length && str[j] != '"'
            if str[j] == '\\'
              j += 2
            elsif (skip = skip_expansion(str, j))
              j = skip
            else
              j += 1
            end
          end
          yield :double, str[i + 2...j]
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
            if c == '\\'
              # Backslash escapes the next char (incl. a quote), so it is not a
              # segment boundary; keep both for the unescape step downstream.
              j += 2
            elsif c == '$' && j + 1 < str.length
              nc = str[j + 1]
              if nc == "'" || nc == '"'
                break # $'...' and $"..." are segments of their own
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

    # Split the inner text of a plain double-quoted word around "${name[@]}"
    # and "${!name[@]}" expansions. Returns an array of [:text, str],
    # [:array, name] (elements) and [:keys, name] (indices/keys) pairs, or
    # nil when the text contains no such expansion. An expansion preceded by a
    # backslash is literal text. Used so "x${arr[@]}y" can expand to one word
    # per element (with x/y attached to the first/last) instead of collapsing
    # into a single string.
    # Captures: 1 = "!" for keys, 2 = name, 3 = ":off[:len]" slice spec for
    # an array, 4/5 = "@" and its slice spec for ${@:off[:len]}
    ARRAY_AT_EXPANSION = /\$\{(!?)([a-zA-Z_][a-zA-Z0-9_]*)\[@\](?::(?![-=+?])([^}]*))?\}|\$\{(@)(?::(?![-=+?])([^}]*))?\}|\$\{!([a-zA-Z_][a-zA-Z0-9_]*)@\}|\$\{([a-zA-Z_][a-zA-Z0-9_]*)\[@\]([#%\/^,~][^}]*|@[QEPUuL])\}|\$\{@([#%\/^,~][^}]*|@[QEPUuL])\}/

    def self.split_quoted_array_word(inner)
      return nil unless inner.match?(ARRAY_AT_EXPANSION)

      pieces = []
      text = +''
      pos = 0
      inner.scan(ARRAY_AT_EXPANSION) do
        match = Regexp.last_match
        text << inner[pos...match.begin(0)]
        pos = match.end(0)
        if text.end_with?(92.chr) # backslash: escaped, keep literal
          text << match[0]
          next
        end
        pieces << [:text, text] unless text.empty?
        if match[7]
          # ${arr[@]OP...}: OP applied to each element
          pieces << [:op, match[7], match[8]]
        elsif match[9]
          # ${@OP...}
          pieces << [:op, '@', match[9]]
        elsif match[6]
          # ${!prefix@}
          pieces << [:prefix_names, match[6]]
        elsif match[4] || match[5]
          # ${@:off[:len]}
          pieces << (match[5] ? [:slice, '@', match[5]] : [:array, '@'])
        elsif match[3]
          # ${arr[@]:off[:len]}
          pieces << [:slice, match[2], match[3]]
        else
          pieces << [match[1] == '!' ? :keys : :array, match[2]]
        end
        text = +''
      end
      text << inner[pos..]
      pieces << [:text, text] unless text.empty?
      pieces.any? { |type, _| type != :text } ? pieces : nil
    end

    # Returns true when str contains more than one segment (ie. it is an
    # adjacent/mixed quoted word rather than a plain quoted or bare token).
    # Does the word hold a brace expansion, `{a,b}` or `{1..5}`, outside
    # quotes? Quoted text inside the braces (`{a,"b c"}`) is skipped, and
    # `${...}` is a parameter expansion, not a brace list.
    def self.brace_list?(str)
      i = 0
      while i < str.length
        case str[i]
        when '\\' then i += 2; next
        when "'", '"'
          close = str.index(str[i], i + 1)
          return false unless close

          i = close + 1
          next
        when '{'
          unless i > 0 && str[i - 1] == '$'
            depth = 1
            j = i + 1
            has_sep = false
            while j < str.length && depth > 0
              case str[j]
              when "'", '"'
                close = str.index(str[j], j + 1)
                return false unless close

                j = close
              when '{' then depth += 1
              when '}' then depth -= 1
              when ',' then has_sep = true if depth == 1
              when '.' then has_sep = true if depth == 1 && str[j + 1] == '.'
              end
              j += 1
            end
            return true if depth == 0 && has_sep
          end
        end
        i += 1
      end
      false
    end

    # Does an unquoted part of the word have a glob character?
    def self.bare_glob?(str)
      each_segment(str) { |type, content| return true if type == :bare && content.match?(/[*?\[]/) }
      false
    end

    # Does an unquoted part of the word hold an expansion (`$`, backtick)
    # whose result is subject to word splitting? A `$'...'` or "$x" is not.
    def self.bare_expansion?(str)
      each_segment(str) { |type, content| return true if type == :bare && content.match?(/[$`]/) }
      false
    end

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
        if c == '\\'
          # Escaped char (incl. a quote) is not a segment boundary.
          j += 2
        elsif c == '$' && j + 1 < str.length
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
