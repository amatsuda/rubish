# frozen_string_literal: true

module Rubish
  class Lexer
    Token = Data.define(:type, :value)

    OPERATORS = {
      '|' => :PIPE,
      ';' => :SEMICOLON,
      ';;' => :DOUBLE_SEMI,  # For case statement pattern terminators
      '&' => :AMPERSAND,
      '>' => :REDIRECT_OUT,
      '>>' => :REDIRECT_APPEND,
      '<' => :REDIRECT_IN,
      '<<' => :HEREDOC,      # Here document
      '<<-' => :HEREDOC_INDENT,  # Here document with indented delimiter
      '<<<' => :HERESTRING,  # Here string
      '2>' => :REDIRECT_ERR,
      '&&' => :AND,
      '||' => :OR,
      '(' => :LPAREN,
      ')' => :RPAREN,
      '()' => :PARENS,  # For function definitions: name() { }
      '{' => :LBRACE,
      '}' => :RBRACE
    }.freeze

    KEYWORDS = {
      'if' => :IF,
      'then' => :THEN,
      'else' => :ELSE,
      'elif' => :ELIF,
      'fi' => :FI,
      'while' => :WHILE,
      'until' => :UNTIL,
      'for' => :FOR,
      'select' => :SELECT,
      'function' => :FUNCTION,
      'case' => :CASE,
      'esac' => :ESAC
      # Note: 'do', 'done', 'in' are handled as WORD tokens and checked by parser
      # to allow them as command arguments (e.g., "echo done")
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
      three_char = @input[@pos, 3]
      if three_char == '<<<'
        @pos += 3
        return read_herestring
      elsif three_char == '<<-'
        @pos += 3
        return read_heredoc_delimiter(:HEREDOC_INDENT)
      end

      two_char = @input[@pos, 2]
      if two_char == '<<'
        @pos += 2
        return read_heredoc_delimiter(:HEREDOC)
      end
      # Process substitution: <(...) and >(...)
      if two_char == '<('
        return read_process_substitution(:PROC_SUB_IN)
      end
      if two_char == '>('
        return read_process_substitution(:PROC_SUB_OUT)
      end
      if %w[>> 2> && || () ;;].include?(two_char)
        @pos += 2
        return Token.new(OPERATORS[two_char], two_char)
      end

      # Single char operators
      # Note: () is handled above as two-char for function defs, so ( here is for subshells
      char = @input[@pos]
      if %w[| ; & > ) (].include?(char)
        @pos += 1
        return Token.new(OPERATORS[char], char)
      end
      # < alone is redirect in (heredocs handled above)
      if char == '<'
        @pos += 1
        return Token.new(:REDIRECT_IN, char)
      end

      # Ruby literals
      case char
      when '['
        # Check if this is a command [ (test) or an array literal
        # [ as command is followed by space, array literal is not
        if @input[@pos + 1] =~ /[\s]/
          @pos += 1
          return Token.new(:WORD, '[')
        end
        # Check if this is a glob pattern like [abc]file vs array [1, 2, 3]
        # Glob pattern: [chars] followed by more word characters
        # Array: [value, value, ...] with commas inside
        if looks_like_glob_bracket?
          read_word
        else
          read_array
        end
      when '/'
        read_regexp_or_word
      when '{'
        # Check if this is a brace expansion pattern like {a,b,c} or {1..5}
        if looks_like_brace_expansion?
          read_word
        else
          # Check if this is a Ruby block { |x| ... } or shell function body { cmd; }
          # Ruby blocks have | after optional whitespace
          lookahead = @pos + 1
          lookahead += 1 while lookahead < @input.length && @input[lookahead] =~ /\s/
          if @input[lookahead] == '|'
            read_block
          else
            # Shell function body or standalone brace
            @pos += 1
            Token.new(:LBRACE, '{')
          end
        end
      when '}'
        @pos += 1
        Token.new(:RBRACE, '}')
      when 'd'
        # Check for Ruby 'do' block (do |x| ... end)
        # Only treat as block if followed by space/| (not 'done' or other words)
        if @input[@pos, 2] == 'do' && @input[@pos + 2] =~ /[\s|]/
          # Look ahead to see if this has block args (|...|) - distinguishes from shell 'do'
          lookahead = @pos + 2
          lookahead += 1 while lookahead < @input.length && @input[lookahead] =~ /\s/
          if @input[lookahead] == '|'
            read_do_block
          else
            read_word
          end
        else
          read_word
        end
      else
        read_word
      end
    end

    def looks_like_glob_bracket?
      # Glob pattern: [abc] or [a-z] followed by more word characters
      # Array: [1, 2, 3] or ["a", "b"] with commas
      lookahead = @pos + 1
      has_comma = false
      while lookahead < @input.length
        char = @input[lookahead]
        if char == ']'
          # Found closing bracket - check what follows
          next_char = @input[lookahead + 1]
          # If followed by word characters, it's a glob pattern
          return true if next_char && next_char =~ /[a-zA-Z0-9_.\-]/
          # If followed by space/operator/end, could be either
          # Check if we saw commas inside - if so, it's an array
          return !has_comma
        elsif char == ','
          has_comma = true
        elsif char =~ /[\s]/
          # Whitespace inside brackets suggests array (glob patterns are compact)
          return false
        end
        lookahead += 1
      end
      false  # Unclosed bracket, treat as array
    end

    def looks_like_brace_expansion?
      # Brace expansion: {a,b,c} or {1..5} or prefix{a,b}suffix
      # Must have matching braces with comma or ..
      # Not: ${VAR} (variable) or { cmd; } (function body)
      lookahead = @pos + 1
      depth = 1
      has_comma = false
      has_dotdot = false

      while lookahead < @input.length && depth > 0
        char = @input[lookahead]
        case char
        when '{'
          depth += 1
        when '}'
          depth -= 1
        when ','
          has_comma = true if depth == 1
        when '.'
          if @input[lookahead + 1] == '.'
            has_dotdot = true if depth == 1
            lookahead += 1  # Skip second dot
          end
        when ' ', "\t", "\n"
          # Whitespace inside braces suggests function body, not brace expansion
          return false if depth > 0
        end
        lookahead += 1
      end

      # Must have found closing brace and have either comma or ..
      depth == 0 && (has_comma || has_dotdot)
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
          # If followed by whitespace, operator (except {), or end, it's a regexp
          # Exclude { because it could be brace expansion in a path like /tmp/{a,b}
          next_char = @input[after_slash]
          if next_char.nil? || next_char =~ /[ \t]/ || (OPERATORS.key?(next_char) && next_char != '{')
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

        # Handle { specially BEFORE the general operator check
        # { could be brace expansion (part of word) or operator
        if char == '{'
          if @pos > start && @input[@pos - 1] == '$'
            # ${VAR} - variable expansion, let read_braced_variable handle it below
          elsif looks_like_brace_expansion?
            # Brace expansion pattern like {a,b,c} - read the whole thing
            read_brace_expansion
            next
          else
            # Not brace expansion (e.g. shell function body), treat as operator
            break
          end
        end

        # General break conditions - exclude { since it's handled above
        break if char =~ /[ \t]/ || (OPERATORS.key?(char) && char != '{')
        break if @input[@pos, 2] == '>>' || @input[@pos, 2] == '2>' || @input[@pos, 2] == ';;'
        # Stop at Ruby literal starters only at the start of a word
        # In the middle of a word, [ is a glob pattern like file[12].txt
        # At the start, [ might be a glob pattern like [abc]file
        # Exception: ${VAR} is a shell variable, not a Ruby block
        break if char == '[' && @pos == start && !looks_like_glob_bracket?

        if char == '"'
          read_double_quoted_string
        elsif char == "'"
          read_single_quoted_string
        elsif char == '`'
          # Backtick command substitution `...`
          read_backtick_substitution
        elsif char == '$' && @input[@pos + 1] == '('
          # Command substitution $(...)
          read_command_substitution
        elsif char == '$' && @input[@pos + 1] == '{'
          # Variable expansion ${VAR}
          read_braced_variable
        else
          @pos += 1
        end
      end
      value = @input[start...@pos]
      return nil if value.empty?

      # Check if word is a keyword
      if KEYWORDS.key?(value)
        Token.new(KEYWORDS[value], value)
      else
        Token.new(:WORD, value)
      end
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

    def read_command_substitution
      # $(...)
      @pos += 2 # skip $(
      depth = 1
      while @pos < @input.length && depth > 0
        char = @input[@pos]
        if char == '('
          depth += 1
        elsif char == ')'
          depth -= 1
        elsif char == '"'
          read_double_quoted_string
          next
        elsif char == "'"
          read_single_quoted_string
          next
        end
        @pos += 1
      end
    end

    def read_backtick_substitution
      # `...`
      @pos += 1 # skip opening `
      while @pos < @input.length
        char = @input[@pos]
        if char == '\\'
          # Skip escaped character (including escaped backtick)
          @pos += 2
          next
        elsif char == '`'
          @pos += 1 # skip closing `
          break
        end
        @pos += 1
      end
    end

    def read_braced_variable
      # ${VAR}
      @pos += 2 # skip ${
      @pos += 1 while @pos < @input.length && @input[@pos] != '}'
      @pos += 1 if @pos < @input.length # skip closing }
    end

    def read_brace_expansion
      # Read a brace expansion pattern like {a,b,c} or {1..5}
      # Handles nested braces
      depth = 0
      while @pos < @input.length
        char = @input[@pos]
        if char == '{'
          depth += 1
        elsif char == '}'
          depth -= 1
          @pos += 1
          break if depth == 0
          next
        end
        @pos += 1
      end
    end

    def read_process_substitution(type)
      # Read <(...) or >(...) - the command inside parens
      @pos += 2  # skip <( or >(
      start = @pos
      depth = 1
      while @pos < @input.length && depth > 0
        char = @input[@pos]
        if char == '('
          depth += 1
        elsif char == ')'
          depth -= 1
          break if depth == 0
        elsif char == '"'
          read_double_quoted_string
          next
        elsif char == "'"
          read_single_quoted_string
          next
        end
        @pos += 1
      end
      command = @input[start...@pos]
      @pos += 1 if @pos < @input.length  # skip closing )
      Token.new(type, command)
    end

    def read_heredoc_delimiter(type)
      skip_whitespace

      # Check for quoted delimiter (no variable expansion)
      quoted = false
      if @input[@pos] == "'" || @input[@pos] == '"'
        quote = @input[@pos]
        @pos += 1
        start = @pos
        @pos += 1 while @pos < @input.length && @input[@pos] != quote
        delimiter = @input[start...@pos]
        @pos += 1 if @pos < @input.length # skip closing quote
        quoted = true
      else
        # Unquoted delimiter
        start = @pos
        @pos += 1 while @pos < @input.length && @input[@pos] =~ /[a-zA-Z0-9_]/
        delimiter = @input[start...@pos]
      end

      # Return token with delimiter info: "delimiter:quoted" format
      # quoted=true means no variable expansion
      value = quoted ? "#{delimiter}:quoted" : delimiter
      Token.new(type, value)
    end

    def read_herestring
      skip_whitespace

      # Read the string (can be quoted or unquoted)
      if @input[@pos] == '"'
        start = @pos
        read_double_quoted_string
        value = @input[start...@pos]
      elsif @input[@pos] == "'"
        start = @pos
        read_single_quoted_string
        value = @input[start...@pos]
      else
        # Unquoted - read until whitespace or operator
        start = @pos
        while @pos < @input.length
          char = @input[@pos]
          break if char =~ /[ \t]/ || OPERATORS.key?(char)
          @pos += 1
        end
        value = @input[start...@pos]
      end

      Token.new(:HERESTRING, value)
    end
  end
end
