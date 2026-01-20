# frozen_string_literal: true

module Rubish
  class Lexer
    Token = Data.define(:type, :value)

    OPERATORS = {
      '|' => :PIPE,
      '|&' => :PIPE_BOTH,    # Pipe stdout and stderr: cmd1 |& cmd2 = cmd1 2>&1 | cmd2
      ';' => :SEMICOLON,
      ';;' => :DOUBLE_SEMI,  # For case statement pattern terminators
      ';&' => :CASE_FALL,    # Case fall-through (execute next pattern)
      ';;&' => :CASE_CONT,   # Case continue (test next pattern)
      '&' => :AMPERSAND,
      '>' => :REDIRECT_OUT,
      '>|' => :REDIRECT_CLOBBER,  # Force overwrite even with noclobber
      '>>' => :REDIRECT_APPEND,
      '<' => :REDIRECT_IN,
      '<<' => :HEREDOC,      # Here document
      '<<-' => :HEREDOC_INDENT,  # Here document with indented delimiter
      '<<<' => :HERESTRING,  # Here string
      '2>' => :REDIRECT_ERR,
      '>&' => :DUP_OUT,       # Duplicate output FD
      '<&' => :DUP_IN,        # Duplicate input FD
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
      'unless' => :UNLESS,
      'then' => :THEN,
      'else' => :ELSE,
      'elif' => :ELIF,
      'elsif' => :ELSIF,
      'fi' => :FI,
      'while' => :WHILE,
      'until' => :UNTIL,
      'for' => :FOR,
      'select' => :SELECT,
      'function' => :FUNCTION,
      'def' => :DEF,
      'case' => :CASE,
      'when' => :WHEN,
      'esac' => :ESAC,
      'coproc' => :COPROC,
      'time' => :TIME
      # Note: 'do', 'done', 'in', 'end' are handled as WORD tokens and checked by parser
      # to allow them as command arguments (e.g., "echo done")
    }.freeze

    def initialize(input)
      @input = input
      @pos = 0
      @last_token_type = nil
      @last_word_value = nil
    end

    def tokenize
      tokens = []
      while @pos < @input.length
        skip_whitespace
        break if @pos >= @input.length

        token = read_token
        if token
          tokens << token
          @last_token_type = token.type
          # Track word value for block detection (also SELECT for filtering select)
          @last_word_value = token.value if token.type == :WORD || token.type == :SELECT
        end
      end
      tokens
    end

    private

    def skip_whitespace
      @pos += 1 while @pos < @input.length && @input[@pos] =~ /[ \t\n]/
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

      # Check for {varname} redirection pattern: {fd}>file, {fd}<file, etc.
      if @input[@pos] == '{' && looks_like_varname_redirect?
        return read_varname_redirect
      end

      two_char = @input[@pos, 2]
      if two_char == '<<'
        @pos += 2
        return read_heredoc_delimiter(:HEREDOC)
      end
      # Arithmetic command (( )) - only when in command position
      # Distinguish from nested subshell: ((cmd)) vs (( expr ))
      # If followed by a word then space (like "echo "), it's likely a nested subshell
      if two_char == '(('
        # Look ahead to see if this looks like an arithmetic expression
        # Skip whitespace to find what comes after ((
        lookahead_pos = @pos + 2
        while lookahead_pos < @input.length && @input[lookahead_pos] =~ /[ \t]/
          lookahead_pos += 1
        end
        # Arithmetic expressions start with: number, variable (optionally with $),
        # unary operators (!, -, ~, ++, --), or (
        # Commands start with: letter followed by space, or are builtins like echo, cd, etc.
        first_content = @input[lookahead_pos, 30] || ''
        # It's arithmetic if it starts with:
        # - A number (possibly negative)
        # - $ (variable reference)
        # - ! or ~ (unary operators)
        # - identifier followed by arithmetic operator (=, +, -, ++, --, *, /, etc.)
        # - ( followed by space or non-alpha (grouped expression, not command)
        # Note: We must NOT match patterns like ((abc)(123)) which is regex grouping
        is_arithmetic = case first_content
                        when /\A-?\d/ then true  # Number
                        when /\A\$/ then true    # Variable reference
                        when /\A[!~]/ then true  # Unary operators
                        when /\A(\+\+|--)[a-zA-Z_]/ then true  # Pre-increment/decrement
                        when /\A[a-zA-Z_][a-zA-Z0-9_]*\s*(\+\+|--|[=+\-*\/%<>&|^]=?|\[)/ then true  # Identifier with operator
                        when /\A\(\s*[\d$!~(+-]/ then true  # Grouped expression starting with arith
                        when /\A;/ then true  # Empty init in for ((; cond; update))
                        else false
                        end
        if is_arithmetic
          @pos += 2
          return read_arithmetic_command
        end
        # Otherwise fall through to handle as nested subshells
      end
      # Extended test command [[ ]] - only when in command position
      # Not when it's a nested array like [[1, 2], [3, 4]]
      if two_char == '[['
        # Check if followed by space (conditional) or digit/quote (array)
        next_char = @input[@pos + 2]
        if next_char.nil? || next_char =~ /[\s\-!]/
          @pos += 2
          return Token.new(:DOUBLE_LBRACKET, '[[')
        end
        # Otherwise it's a nested array, fall through to array handling
      end
      if two_char == ']]'
        @pos += 2
        return Token.new(:DOUBLE_RBRACKET, ']]')
      end
      # Process substitution: <(...) and >(...)
      if two_char == '<('
        return read_process_substitution(:PROC_SUB_IN)
      end
      if two_char == '>('
        return read_process_substitution(:PROC_SUB_OUT)
      end
      # Check for three-char operators first: ;;&
      three_char_op = @input[@pos, 3]
      if three_char_op == ';;&'
        @pos += 3
        return Token.new(:CASE_CONT, ';;&')
      end
      if %w[>> >| 2> >& <& && || () ;; ;& |&].include?(two_char)
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
          elsif @last_word_value == 'each' || @last_word_value == '.each' ||
                @last_word_value == 'map' || @last_word_value == '.map' ||
                @last_word_value == 'select' || @last_word_value == '.select'
            # Block after 'each'/'map'/'select' without explicit variable: each { body }
            # Uses implicit 'it' variable (accessed as $it)
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
      when '.'
        # Check if this is a method chain: .identifier(
        # Not: .hidden (hidden file), ./path (relative path)
        if looks_like_method_chain_start?
          @pos += 1
          Token.new(:DOT, '.')
        else
          read_word
        end
      when 'd'
        # Check for Ruby 'do' block (do |x| ... end or do ... end after 'each')
        # Only treat as block if followed by space/| (not 'done' or other words)
        if @input[@pos, 2] == 'do' && @input[@pos + 2] =~ /[\s|]/
          # Look ahead to see if this has block args (|...|) - distinguishes from shell 'do'
          lookahead = @pos + 2
          lookahead += 1 while lookahead < @input.length && @input[lookahead] =~ /\s/
          if @input[lookahead] == '|'
            read_do_block
          elsif @last_word_value == 'each' || @last_word_value == '.each' ||
                @last_word_value == 'map' || @last_word_value == '.map' ||
                @last_word_value == 'select' || @last_word_value == '.select'
            # Block after 'each'/'map'/'select' without explicit variable: each do body end
            # Uses implicit 'it' variable (accessed as $it)
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
      # Path: /foo/bar (continues after the closing /) or /bin/ (trailing slash)
      lookahead = @pos + 1
      while lookahead < @input.length
        char = @input[lookahead]
        break if char =~ /[ \t]/
        if char == '/' && lookahead > @pos + 1
          # Check what comes after the potential closing /
          after_slash = lookahead + 1
          # Skip optional regexp flags
          after_slash += 1 while after_slash < @input.length && @input[after_slash] =~ /[imxo]/
          # If followed by whitespace, operator (except {), or end, it might be a regexp
          # Exclude { because it could be brace expansion in a path like /tmp/{a,b}
          next_char = @input[after_slash]
          if next_char.nil? || next_char =~ /[ \t]/ || (OPERATORS.key?(next_char) && next_char != '{')
            # Check if content looks like a path (no regex metacharacters) or a regexp
            # Paths like /bin/ or /opt/homebrew/ contain alphanumeric, underscore, dash, dot, slash
            # Regexps typically have metacharacters like * + ? ^ $ [ ] ( ) | \
            content = @input[@pos + 1...lookahead]
            if content =~ /\A[a-zA-Z0-9_.\-\/]+\z/
              # Looks like a path component, not a regexp - treat as word
              break
            end
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
        break if char =~ /[ \t\n]/ || (OPERATORS.key?(char) && char != '{')
        break if @input[@pos, 2] == '>>' || @input[@pos, 2] == '2>' || @input[@pos, 2] == ';;'
        # Stop at Ruby literal starters only at the start of a word
        # In the middle of a word, [ is a glob pattern like file[12].txt
        # At the start, [ might be a glob pattern like [abc]file
        # Exception: ${VAR} is a shell variable, not a Ruby block
        break if char == '[' && @pos == start && !looks_like_glob_bracket?
        # Stop at . if it's a method chain (e.g., ls.grep(/foo/))
        # But not for filenames like file.txt or paths like ./script
        break if char == '.' && looks_like_method_chain_start?

        if char == '\\'
          # Backslash escape - skip the next character
          @pos += 2
        elsif char == '"'
          read_double_quoted_string
        elsif char == '$' && @input[@pos + 1] == "'"
          # $'...' ANSI-C quoting - handle escape sequences including \'
          read_ansi_c_quoted_string
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

      # Check for array assignment: VAR=(...) or VAR+=(...)
      if (value.end_with?('=') || value.end_with?('+=')) && @input[@pos] == '('
        return read_array_assignment(value)
      end

      # Check for function call syntax: cmd(arg1, arg2) - but not:
      # - cmd() which is function def
      # - extglob patterns like word?(pat), word*(pat), word+(pat), @(pat), !(pat)
      # - after def/function keywords (where the word is a function name being defined)
      # - words that don't look like command names (e.g., regex metacharacters like ^ or $)
      # - Ruby-like code (contains keyword args with :, nested method calls, etc.)
      if @input[@pos] == '(' && @input[@pos + 1] != ')' &&
         !extglob_prefix?(value) && ![:DEF, :FUNCTION].include?(@last_token_type) &&
         valid_func_call_name?(value) && !looks_like_ruby_call?
        return read_func_call(value)
      end

      # Check if word is a keyword
      if KEYWORDS.key?(value)
        Token.new(KEYWORDS[value], value)
      else
        Token.new(:WORD, value)
      end
    end

    def read_array_assignment(var_part)
      # Read array contents: (elem1 elem2 elem3)
      @pos += 1  # skip opening (
      elements = []

      while @pos < @input.length
        skip_whitespace
        break if @input[@pos] == ')'

        elem = read_array_element
        elements << elem if elem && !elem.empty?
      end

      @pos += 1 if @input[@pos] == ')'  # skip closing )

      Token.new(:ARRAY_ASSIGN, {var: var_part, elements: elements})
    end

    def read_array_element
      start = @pos

      while @pos < @input.length
        char = @input[@pos]

        # Stop at whitespace or closing paren
        break if char =~ /[ \t\n]/ || char == ')'

        if char == '"'
          read_double_quoted_string
        elsif char == '$' && @input[@pos + 1] == "'"
          read_ansi_c_quoted_string
        elsif char == "'"
          read_single_quoted_string
        elsif char == '$' && @input[@pos + 1] == '('
          read_command_substitution
        elsif char == '$' && @input[@pos + 1] == '{'
          read_braced_variable
        else
          @pos += 1
        end
      end

      @input[start...@pos]
    end

    def read_func_call(name)
      # Read function call syntax: cmd(arg1, arg2, ...)
      @pos += 1  # skip opening (
      args = []

      while @pos < @input.length
        # Skip whitespace
        @pos += 1 while @pos < @input.length && @input[@pos] =~ /[ \t]/

        break if @input[@pos] == ')'

        arg = read_func_call_arg
        args << arg if arg && !arg.empty?

        # Skip whitespace after arg
        @pos += 1 while @pos < @input.length && @input[@pos] =~ /[ \t]/

        # Check for comma or closing paren
        if @input[@pos] == ','
          @pos += 1  # skip comma
        elsif @input[@pos] == ')'
          break
        else
          # Unexpected character, stop parsing
          break
        end
      end

      @pos += 1 if @input[@pos] == ')'  # skip closing )

      Token.new(:FUNC_CALL, {name: name, args: args})
    end

    def read_func_call_arg
      start = @pos

      # Check for special cases first
      char = @input[@pos]

      # Quoted strings
      if char == '"'
        read_double_quoted_string
        return @input[start...@pos]
      elsif char == "'"
        read_single_quoted_string
        return @input[start...@pos]
      elsif char == '$' && @input[@pos + 1] == "'"
        read_ansi_c_quoted_string
        return @input[start...@pos]
      end

      # Check for regexp or path starting with /
      if char == '/'
        return read_func_call_slash_arg
      end

      # Check for array literal
      if char == '['
        read_array
        return @input[start...@pos]
      end

      # Regular word argument
      while @pos < @input.length
        char = @input[@pos]

        # Stop at comma, closing paren, or whitespace
        break if char =~ /[ \t]/ || char == ',' || char == ')'

        if char == '\\'
          @pos += 2
        elsif char == '"'
          read_double_quoted_string
        elsif char == "'"
          read_single_quoted_string
        elsif char == '$' && @input[@pos + 1] == '('
          read_command_substitution
        elsif char == '$' && @input[@pos + 1] == '{'
          read_braced_variable
        else
          @pos += 1
        end
      end

      @input[start...@pos]
    end

    def read_func_call_slash_arg
      # Determine if /.../ is a path or regexp inside function call
      # Path: contains only alphanumeric, _, ., -, /
      # Regexp: contains metacharacters like *, +, ?, ^, $, [, ], (, ), |, \
      start = @pos
      @pos += 1  # skip opening /

      has_metachar = false
      closed = false

      while @pos < @input.length
        char = @input[@pos]

        # Stop at comma, closing paren (without closing /), or whitespace
        if char =~ /[ \t]/ || char == ',' || char == ')'
          break
        end

        if char == '/'
          # Check if this looks like end of regexp or middle of path
          # If we've seen metacharacters, it's likely a regexp
          # If content is path-like, continue as path
          content = @input[start + 1...@pos]
          if has_metachar || content !~ /\A[a-zA-Z0-9_.\-\/]*\z/
            # Regexp - consume closing / and optional flags
            @pos += 1
            @pos += 1 while @pos < @input.length && @input[@pos] =~ /[imxo]/
            closed = true
            break
          else
            # Path - continue reading
            @pos += 1
          end
        elsif char == '\\' && has_metachar
          # Escape in regexp
          @pos += 2
        elsif char =~ /[*+?^$\[\]()|\\.]/
          has_metachar = true
          @pos += 1
        else
          @pos += 1
        end
      end

      @input[start...@pos]
    end

    def extglob_prefix?(word)
      # Check if word ends with extglob prefix: ?, *, +, @, !
      # These form patterns like foo?(bar), *(pat), @(a|b), !(neg)
      return true if word.empty?  # standalone @( or !( etc.
      return true if word =~ /[?*+@!]\z/
      # Also check for patterns that are entirely glob characters
      return true if word =~ /\A[*?@!]+\z/
      false
    end

    def looks_like_method_chain_start?
      # Check if current position (at '.') starts a method chain:
      # - .identifier(args) - method call with args
      # - .identifier { block } - method call with block (like .each {|x| ...})
      return false unless @input[@pos] == '.'

      lookahead = @pos + 1
      # Must start with letter or underscore (not / for paths or digit for decimals)
      return false unless lookahead < @input.length && @input[lookahead] =~ /[a-zA-Z_]/

      # Read the identifier
      id_start = lookahead
      lookahead += 1
      lookahead += 1 while lookahead < @input.length && @input[lookahead] =~ /[a-zA-Z0-9_]/
      identifier = @input[id_start...lookahead]

      # Skip optional whitespace
      block_lookahead = lookahead
      block_lookahead += 1 while block_lookahead < @input.length && @input[block_lookahead] =~ /[ \t]/

      # Check for block: { followed by |
      if block_lookahead < @input.length && @input[block_lookahead] == '{'
        # Check if this is a Ruby block {|...| or { |...|
        inner = block_lookahead + 1
        inner += 1 while inner < @input.length && @input[inner] =~ /\s/
        return true if inner < @input.length && @input[inner] == '|'
        # For each/map/select, also allow implicit 'it' blocks without |
        return true if %w[each map select].include?(identifier)
      end

      # Must be followed by ( for method call
      return false unless lookahead < @input.length && @input[lookahead] == '('

      # Additional check: not Ruby keyword args inside (to avoid false positives)
      !looks_like_ruby_method_chain?(lookahead)
    end

    def looks_like_ruby_method_chain?(paren_pos)
      # Check if the content inside parens looks like Ruby code
      # Similar to looks_like_ruby_call? but starting from a specific position
      lookahead = paren_pos + 1
      depth = 1
      in_string = false
      string_char = nil

      while lookahead < @input.length && depth > 0
        char = @input[lookahead]

        if !in_string && (char == '"' || char == "'")
          in_string = true
          string_char = char
        elsif in_string && char == string_char && @input[lookahead - 1] != '\\'
          in_string = false
        elsif !in_string
          case char
          when '('
            depth += 1
          when ')'
            depth -= 1
          when ':'
            prev_char = lookahead > 0 ? @input[lookahead - 1] : nil
            next_char = @input[lookahead + 1]
            if prev_char =~ /[a-zA-Z0-9_]/ && (next_char.nil? || next_char =~ /[\s\w]/)
              return true
            end
          end
        end

        lookahead += 1
      end

      false
    end

    def valid_func_call_name?(name)
      # Valid function/command names must start with letter, underscore, or be a path
      # Not valid: regex metacharacters like ^, $, or single special chars
      return false if name.empty?
      # Must start with letter, underscore, digit, dot, or / (for paths like /bin/ls)
      return false unless name =~ /\A[a-zA-Z_0-9.\/]/
      # Must not be just special characters
      return false if name =~ /\A[\^$]+\z/
      true
    end

    def looks_like_ruby_call?
      # Check if the content inside parens looks like Ruby code rather than shell args
      # Look ahead from current position (which is at '(')
      lookahead = @pos + 1
      depth = 1
      in_string = false
      string_char = nil

      while lookahead < @input.length && depth > 0
        char = @input[lookahead]

        # Track string state
        if !in_string && (char == '"' || char == "'")
          in_string = true
          string_char = char
        elsif in_string && char == string_char && @input[lookahead - 1] != '\\'
          in_string = false
        elsif !in_string
          case char
          when '('
            depth += 1
          when ')'
            depth -= 1
          when ':'
            # Check for Ruby keyword arg syntax: identifier followed by : and space/value
            # e.g., "foo: bar" or "foo:bar" but not ":/path" or "$:"
            prev_char = lookahead > 0 ? @input[lookahead - 1] : nil
            next_char = @input[lookahead + 1]
            # If : follows a word character and precedes space or word, it's likely Ruby
            if prev_char =~ /[a-zA-Z0-9_]/ && (next_char.nil? || next_char =~ /[\s\w]/)
              return true
            end
          end
        end

        lookahead += 1
      end

      false
    end

    def read_double_quoted_string
      @pos += 1 # skip opening "
      while @pos < @input.length && @input[@pos] != '"'
        if @input[@pos] == '\\'
          @pos += 2 # skip escaped char
          next
        end
        @pos += 1
      end
      @pos += 1 # skip closing "
    end

    def read_single_quoted_string
      @pos += 1 # skip opening '
      @pos += 1 while @pos < @input.length && @input[@pos] != "'"
      @pos += 1 # skip closing '
    end

    def read_ansi_c_quoted_string
      # $'...' - ANSI-C quoting with escape sequences
      @pos += 2 # skip $'
      while @pos < @input.length
        char = @input[@pos]
        if char == '\\'
          # Skip escaped character (including \')
          @pos += 2
        elsif char == "'"
          @pos += 1 # skip closing '
          break
        else
          @pos += 1
        end
      end
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

    def read_arithmetic_command
      # Read the arithmetic expression until ))
      # Need to handle nested parentheses
      expression = +''
      depth = 1  # We've already consumed the opening ((

      while @pos < @input.length && depth > 0
        char = @input[@pos]
        two_char = @input[@pos, 2]

        if two_char == '))'
          depth -= 1
          if depth == 0
            @pos += 2
            break
          else
            expression << '))'
            @pos += 2
          end
        elsif two_char == '(('
          depth += 1
          expression << '(('
          @pos += 2
        elsif char == '('
          expression << char
          @pos += 1
        elsif char == ')'
          expression << char
          @pos += 1
        else
          expression << char
          @pos += 1
        end
      end

      raise 'Expected ")))" to close arithmetic command' if depth > 0

      Token.new(:ARITH_CMD, expression.strip)
    end

    # Check if current position is a {varname} redirection pattern
    # Pattern: {identifier} followed by >, >>, <, >&, <&
    def looks_like_varname_redirect?
      return false unless @input[@pos] == '{'

      # Look for closing } followed by redirection operator
      lookahead = @pos + 1
      # Identifier must start with letter or underscore
      return false unless lookahead < @input.length && @input[lookahead] =~ /[a-zA-Z_]/

      # Find the closing brace
      lookahead += 1
      lookahead += 1 while lookahead < @input.length && @input[lookahead] =~ /[a-zA-Z0-9_]/

      # Must be followed by }
      return false unless lookahead < @input.length && @input[lookahead] == '}'

      # Must be followed by a redirection operator
      after_brace = lookahead + 1
      return false unless after_brace < @input.length

      next_two = @input[after_brace, 2]
      next_one = @input[after_brace]

      # Check for valid redirection operators
      %w[>> >| >& <& < >].any? { |op| @input[after_brace, op.length] == op }
    end

    # Read a {varname} redirection: {fd}>file or {fd}<file
    def read_varname_redirect
      @pos += 1  # skip opening {

      # Read variable name
      start = @pos
      @pos += 1 while @pos < @input.length && @input[@pos] =~ /[a-zA-Z0-9_]/
      varname = @input[start...@pos]

      @pos += 1  # skip closing }

      # Read the redirection operator
      two_char = @input[@pos, 2]
      if %w[>> >| >& <&].include?(two_char)
        op = two_char
        @pos += 2
      else
        op = @input[@pos]  # Single char: > or <
        @pos += 1
      end

      # Return token with varname and operator info
      Token.new(:VARNAME_REDIRECT, {varname: varname, operator: op})
    end
  end
end
