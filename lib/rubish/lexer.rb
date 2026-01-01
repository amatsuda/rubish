# frozen_string_literal: true

module Rubish
  class Lexer
    Token = Data.define(:type, :value)

    OPERATORS = {
      '|' => :PIPE,
      ';' => :SEMICOLON,
      '&' => :AMPERSAND,
      '>' => :REDIRECT_OUT,
      '>>' => :REDIRECT_APPEND,
      '<' => :REDIRECT_IN,
      '2>' => :REDIRECT_ERR,
      '&&' => :AND,
      '||' => :OR
    }.freeze

    def initialize(input)
      @input = input
      @pos = 0
    end

    def tokenize
      tokens = []
      while @pos < @input.length
        skip_whitespace
        break if @pos >= @input.length

        token = read_token
        tokens << token if token
      end
      tokens
    end

    private

    def skip_whitespace
      @pos += 1 while @pos < @input.length && @input[@pos] =~ /[ \t]/
    end

    def read_token
      # Check for multi-char operators first
      two_char = @input[@pos, 2]
      if %w[>> 2> && ||].include?(two_char)
        @pos += 2
        return Token.new(OPERATORS[two_char], two_char)
      end

      # Single char operators
      char = @input[@pos]
      if OPERATORS.key?(char)
        @pos += 1
        return Token.new(OPERATORS[char], char)
      end

      # Ruby literals
      case char
      when '['
        read_array
      when '/'
        read_regexp_or_word
      when '{'
        read_block
      when 'd'
        # Check for 'do' block
        if @input[@pos, 2] == 'do' && (@input[@pos + 2].nil? || @input[@pos + 2] =~ /[\s|]/)
          read_do_block
        else
          read_word
        end
      else
        read_word
      end
    end

    def read_array
      start = @pos
      depth = 0
      while @pos < @input.length
        char = @input[@pos]
        if char == '['
          depth += 1
        elsif char == ']'
          depth -= 1
          if depth == 0
            @pos += 1
            break
          end
        elsif char == '"'
          read_double_quoted_string
          next
        elsif char == "'"
          read_single_quoted_string
          next
        end
        @pos += 1
      end
      Token.new(:ARRAY, @input[start...@pos])
    end

    def read_regexp_or_word
      # Look ahead to see if this is a regexp or a path
      # Regexp: /pattern/ followed by whitespace, operator, or end
      # Path: /foo/bar (continues after the closing /)
      lookahead = @pos + 1
      while lookahead < @input.length
        char = @input[lookahead]
        break if char =~ /[ \t]/
        if char == '/' && lookahead > @pos + 1
          # Check what comes after the potential closing /
          after_slash = lookahead + 1
          # Skip optional regexp flags
          after_slash += 1 while after_slash < @input.length && @input[after_slash] =~ /[imxo]/
          # If followed by whitespace, operator, or end, it's a regexp
          next_char = @input[after_slash]
          if next_char.nil? || next_char =~ /[ \t]/ || OPERATORS.key?(next_char)
            return read_regexp
          end
          # Otherwise continue - it's a path like /tmp/file
        end
        # Check for escape in regexp
        if char == '\\'
          lookahead += 2
          next
        end
        lookahead += 1
      end
      # Not a regexp, treat as word
      read_word
    end

    def read_regexp
      start = @pos
      @pos += 1 # skip opening /
      while @pos < @input.length
        char = @input[@pos]
        if char == '\\'
          @pos += 2 # skip escaped char
          next
        end
        if char == '/'
          @pos += 1
          # Read optional flags (i, m, x, etc.)
          @pos += 1 while @pos < @input.length && @input[@pos] =~ /[imxo]/
          break
        end
        @pos += 1
      end
      Token.new(:REGEXP, @input[start...@pos])
    end

    def read_block
      start = @pos
      depth = 0
      while @pos < @input.length
        char = @input[@pos]
        if char == '{'
          depth += 1
        elsif char == '}'
          depth -= 1
          if depth == 0
            @pos += 1
            break
          end
        elsif char == '"'
          read_double_quoted_string
          next
        elsif char == "'"
          read_single_quoted_string
          next
        end
        @pos += 1
      end
      Token.new(:BLOCK, @input[start...@pos])
    end

    def read_do_block
      start = @pos
      depth = 1
      @pos += 2 # skip 'do'
      while @pos < @input.length
        # Check for 'do' (increase depth)
        if @input[@pos, 2] == 'do' && (@pos == 0 || @input[@pos - 1] =~ /\s/) &&
           (@input[@pos + 2].nil? || @input[@pos + 2] =~ /[\s|]/)
          depth += 1
          @pos += 2
          next
        end
        # Check for 'end' (decrease depth)
        if @input[@pos, 3] == 'end' && (@pos == 0 || @input[@pos - 1] =~ /\s/) &&
           (@input[@pos + 3].nil? || @input[@pos + 3] =~ /[\s|;]/)
          depth -= 1
          if depth == 0
            @pos += 3
            break
          end
        end
        if @input[@pos] == '"'
          read_double_quoted_string
          next
        elsif @input[@pos] == "'"
          read_single_quoted_string
          next
        end
        @pos += 1
      end
      Token.new(:BLOCK, @input[start...@pos])
    end

    def read_word
      start = @pos
      while @pos < @input.length
        char = @input[@pos]
        break if char =~ /[ \t]/ || OPERATORS.key?(char)
        break if @input[@pos, 2] == '>>' || @input[@pos, 2] == '2>'
        # Stop at Ruby literal starters (but not in the middle of a word)
        break if char == '[' || char == '{'

        if char == '"'
          read_double_quoted_string
        elsif char == "'"
          read_single_quoted_string
        else
          @pos += 1
        end
      end
      value = @input[start...@pos]
      Token.new(:WORD, value) unless value.empty?
    end

    def read_double_quoted_string
      @pos += 1 # skip opening "
      while @pos < @input.length && @input[@pos] != '"'
        @pos += 2 if @input[@pos] == '\\' # skip escaped char
        @pos += 1
      end
      @pos += 1 # skip closing "
    end

    def read_single_quoted_string
      @pos += 1 # skip opening '
      @pos += 1 while @pos < @input.length && @input[@pos] != "'"
      @pos += 1 # skip closing '
    end
  end
end
