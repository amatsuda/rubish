# frozen_string_literal: true

require_relative 'word_segments'

module Rubish
  # String, variable, and parameter expansion for the shell REPL
  # Handles variable expansion, command substitution, tilde expansion, parameter expansion, etc.
  module Expansion
    # Special associative arrays that use string keys (not registered with assoc_array?)
    SPECIAL_ASSOC_ARRAYS = %w[RUBISH_ALIASES BASH_ALIASES RUBISH_CMDS BASH_CMDS].freeze

    # Read-only shell variables that cannot be assigned
    READONLY_SPECIAL_VARS = %w[
      PPID UID EUID GROUPS HOSTNAME RUBISHPID BASHPID HISTCMD
      EPOCHSECONDS EPOCHREALTIME SRANDOM RUBISH_MONOSECONDS BASH_MONOSECONDS
      RUBISH_VERSION BASH_VERSION RUBISH_VERSINFO BASH_VERSINFO
      OSTYPE HOSTTYPE MACHTYPE PIPESTATUS pipestatus RUBISH_COMMAND BASH_COMMAND
      FUNCNAME RUBISH_LINENO BASH_LINENO RUBISH_SOURCE BASH_SOURCE
      RUBISH_ARGC BASH_ARGC RUBISH_ARGV BASH_ARGV RUBISH_SUBSHELL BASH_SUBSHELL
      DIRSTACK COLUMNS LINES RUBISH_ALIASES BASH_ALIASES RUBISH_CMDS BASH_CMDS
      COMP_CWORD COMP_LINE COMP_POINT COMP_TYPE COMP_KEY COMP_WORDS
      RUBISH_EXECUTION_STRING BASH_EXECUTION_STRING RUBISH_REMATCH BASH_REMATCH
      RUBISH BASH RUBISH_TRAPSIG BASH_TRAPSIG
    ].freeze

    def expand_args_for_builtin(args)
      args.flat_map { |arg| expand_single_arg_with_brace_and_glob(arg) }
    end

    def bare_assignment?(str)
      # Check if string is a bare variable assignment: VAR=value, arr=(a b c), or arr[0]=value
      return false unless str.is_a?(String)
      str =~ /\A[a-zA-Z_][a-zA-Z0-9_]*(\[[^\]]*\])?\+?=/
    end

    def extract_array_assignments(line)
      # Check if line contains array assignment(s): arr=(a b c) or arr+=(d e)
      # Returns array of full assignment strings, or nil if not array assignment
      return nil unless line =~ /[a-zA-Z_][a-zA-Z0-9_]*\+?=\(/

      assignments = []
      remaining = line.strip

      while remaining =~ /\A([a-zA-Z_][a-zA-Z0-9_]*\+?=\()/
        prefix = $1
        # Find matching closing paren
        depth = 1
        i = prefix.length
        while i < remaining.length && depth > 0
          case remaining[i]
          when '(' then depth += 1
          when ')' then depth -= 1
          end
          i += 1
        end

        return nil if depth != 0  # Unmatched parens

        assignments << remaining[0...i]
        remaining = remaining[i..].strip
      end

      # If there's remaining content that's not whitespace, this isn't a pure array assignment line
      return nil unless remaining.empty?

      assignments.empty? ? nil : assignments
    end

    # Returns false if an assignment was refused (readonly variable)
    def handle_bare_assignments(assignments)
      ok = true
      assignments.each do |assignment|
        name = assignment[/\A[a-zA-Z_][a-zA-Z0-9_]*/]
        if name && Builtins.readonly?(name)
          $stderr.puts "rubish: #{name}: readonly variable"
          ok = false
          next
        end

        if assignment =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\+?=\((.*)\)\z/m
          handle_array_assignment($1, $2, assignment.include?('+='))
        elsif assignment =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\]=(.*)\z/
          handle_array_element_assignment($1, $2, $3)
        elsif assignment =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)=(.*)\z/m
          handle_scalar_assignment($1, $2)
        end
      end
      ok
    end

    def parse_assoc_array_elements(str)
      # Parse associative array elements: [key1]=value1 [key2]=value2
      pairs = {}
      str.scan(/\[([^\]]+)\]=(\S+|'[^']*'|"[^"]*")/) do |key, value|
        pairs[expand_string_content(key)] = expand_assignment_value(value)
      end
      pairs
    end

    def parse_array_elements(str)
      # Parse array elements, respecting quotes and parentheses
      elements = []
      current = +''
      in_single_quote = false
      in_double_quote = false
      paren_depth = 0

      str.each_char do |char|
        case char
        when "'" then in_single_quote = !in_single_quote unless in_double_quote || paren_depth > 0; current << char
        when '"' then in_double_quote = !in_double_quote unless in_single_quote || paren_depth > 0; current << char
        when '(' then paren_depth += 1 unless in_single_quote || in_double_quote; current << char
        when ')' then paren_depth -= 1 if paren_depth > 0 && !in_single_quote && !in_double_quote; current << char
        when /\s/
          if !in_single_quote && !in_double_quote && paren_depth == 0
            elements.concat(expand_array_element(current)) unless current.empty?
            current = +''
          else
            current << char
          end
        else
          current << char
        end
      end

      elements.concat(expand_array_element(current)) unless current.empty?
      elements
    end

    # Expand an array element, with word splitting for command substitution
    def expand_array_element(value)
      return [''] if value.nil? || value.empty?

      # Pure ${arr[@]} / ${arr[*]} / $arr[@] / $arr[*] — each element of
      # the source array becomes a separate word. Bash/zsh do the same
      # for unquoted array expansion in array-literal context, so
      # `STARSHIP_PIPE_STATUS=(${pipestatus[@]})` produces N elements
      # when pipestatus has N elements, not a single joined string.
      if value =~ /\A\$\{([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\}\z/ ||
         value =~ /\A\$([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\z/
        return __array_values($1)
      end

      # Check if this is purely a command substitution: $(cmd) or `cmd`
      if value =~ /\A\$\(.*\)\z/m || value =~ /\A`.*`\z/m
        expanded = expand_string_content(value)
        ifs = ENV['IFS'] || " \t\n"
        return expanded.split(/[#{Regexp.escape(ifs)}]+/)
      end

      [expand_assignment_value(value)]
    end

    def expand_assignment_value(value)
      return '' if value.nil? || value.empty?
      expand_quoted_string(value) { expand_string_content(value) }
    end

    def expand_single_arg_with_brace_and_glob(arg)
      return [ArrayWord.new(arg.var, expand_args_for_builtin(arg.elements))] if arg.is_a?(AST::ArrayAssign)
      return [arg] unless arg.is_a?(String)

      # "${arr[@]}" keeps one word per element
      words = expand_quoted_array_word(arg)
      return words if words

      # Handle quoted strings
      result = expand_quoted_string(arg) { nil }
      return [result] if result

      # Brace expansion first (only if braceexpand option is enabled)
      brace_expanded = if Builtins.set_option?('B') && arg.include?('{') && !arg.start_with?('$')
                         expand_braces(arg)
                       else
                         [arg]
                       end

      # Then expand variables, apply IFS word splitting, and glob on each result.
      # Per POSIX, IFS word splitting only applies to results of variable expansion,
      # command substitution, and arithmetic expansion -- not to literal text.
      brace_expanded.flat_map do |item|
        expanded = expand_string_content(item)
        if item.include?('$') || item.include?('`')
          # With shwordsplit unset (zsh behavior), scalar variable
          # expansions stay one word. Command substitutions still split
          # (zsh splits those regardless of shwordsplit), and array
          # expansions keep their usual splitting.
          words = if Builtins.zsh_option_enabled?('sh_word_split') ||
                     item.include?('$(') || item.include?('`') ||
                     item =~ /\$\{[a-zA-Z_][a-zA-Z0-9_]*\[[@*]\]/
                    Builtins.split_by_ifs(expanded)
                  else
                    expanded.empty? ? [] : [expanded]
                  end
          words.flat_map { |w| w.match?(/[*?\[]|[+@!]\(/) ? __glob(w) : [w] }
        else
          next [] if expanded.empty?
          expanded.match?(/[*?\[]|[+@!]\(/) ? __glob(expanded) : [expanded]
        end
      end
    end

    def expand_single_arg_with_glob(arg)
      return [arg] unless arg.is_a?(String)

      words = expand_quoted_array_word(arg)
      return words if words

      result = expand_quoted_string(arg) { nil }
      return [result] if result

      expanded = expand_string_content(arg)
      return [] if expanded.empty?
      expanded.match?(/[*?\[]|[+@!]\(/) ? __glob(expanded) : [expanded]
    end

    def expand_single_arg(arg)
      return arg unless arg.is_a?(String)

      result = expand_quoted_string(arg) { nil }
      return result if result

      expand_string_content(arg)
    end

    # Expand variables and command substitution in a string.
    #
    # `quoted:` selects bash's two backslash regimes:
    #   - Inside `"..."` (quoted: true): backslash is only special before
    #     $, `, ", \, or newline. Every other `\X` (incl. `\ ` and `\'`)
    #     is preserved verbatim.
    #   - Unquoted (quoted: false): additionally consume `\<space>` (so
    #     `cd Foo\ Bar/` works) and `\'` (so `echo \'` prints `'`).
    # Other `\X` sequences are still preserved in both regimes — rubish's
    # `echo -e hello\nworld` tests rely on `\n` flowing through, and bind
    # accepts `\C-a` from unquoted args.
    def expand_string_content(str, quoted: false)
      result = +''
      i = 0

      while i < str.length
        char = str[i]

        if char == '\\'
          next_char = str[i + 1]
          if next_char && '$`"\\'.include?(next_char)
            result << next_char
            i += 2
          elsif !quoted && next_char && !'*?[]'.include?(next_char)
            # Unquoted \X is X (quote removal). Glob characters keep their
            # backslash so __glob sees them as literal; it strips it afterwards.
            result << next_char
            i += 2
          else
            # Keep the backslash for other characters (like \C-a in bind,
            # \n inside a DQ string, or any \X in DQ context).
            result << char
            i += 1
          end
        elsif char == '`'
          expanded, consumed = expand_backtick_at(str, i)
          result << expanded
          i += consumed > 0 ? consumed : 1
        elsif char == '$'
          expanded, consumed = expand_variable_at(str, i)
          result << (consumed > 0 ? expanded : char)
          i += consumed > 0 ? consumed : 1
        elsif char == '"'
          i += 1  # Quote removal
        else
          result << char
          i += 1
        end
      end

      result
    end

    # Process $'...' (ANSI-C quoting) and $"..." (locale translation) in a string
    # Used by extquote shopt option for parameter expansion operands
    def expand_extquote(str)
      result = +''
      i = 0

      while i < str.length
        if str[i] == '$' && i + 1 < str.length
          quote_char = str[i + 1]
          if quote_char == "'" || quote_char == '"'
            content, end_pos = extract_quoted_content(str, i + 2, quote_char)
            if end_pos
              if quote_char == "'"
                result << Builtins.process_escape_sequences(content)
              else
                result << __translate(expand_string_content(content, quoted: true))
              end
              i = end_pos + 1
              next
            end
          end
        end
        result << str[i]
        i += 1
      end

      result
    end

    # Expand backtick command substitution at position
    # Returns [expanded_output, characters_consumed]
    def expand_backtick_at(str, pos)
      return ['', 0] unless str[pos] == '`'

      j = pos + 1
      while j < str.length
        if str[j] == '\\'
          j += 2
        elsif str[j] == '`'
          # A backslash inside backticks escapes `, \ and $
          return [__run_subst(str[pos + 1...j].gsub(/\\([`\\$])/, '\1')), j - pos + 1]
        else
          j += 1
        end
      end

      ['', 0]
    end

    # Expand variable/parameter at position in string
    # Handles $VAR, ${VAR}, ${VAR:-default}, $(cmd), $((expr)), and special variables
    # Returns [expanded_value, characters_consumed]
    def expand_variable_at(str, pos)
      return ['', 0] unless str[pos] == '$'

      # Arithmetic expansion $((...))
      if str[pos + 1] == '(' && str[pos + 2] == '('
        end_pos = find_matching_parens(str, pos + 1, 2)
        return [__arith(str[pos + 3...end_pos - 1]), end_pos + 1 - pos] if end_pos
        return ['', 0]
      end

      # Command substitution $(...)
      if str[pos + 1] == '('
        end_pos = find_matching_parens(str, pos + 1, 1)
        return [__run_subst(str[pos + 2...end_pos]), end_pos + 1 - pos] if end_pos
        return ['', 0]
      end

      # Special two-character variables
      two_char = str[pos, 2]
      case two_char
      when '$?' then return [@last_status.to_s, 2]
      when '$$' then return [Process.pid.to_s, 2]
      when '$!' then return [@last_bg_pid&.to_s || '', 2]
      when '$0' then return [argv0, 2]
      when '$#' then return [@positional_params.length.to_s, 2]
      when '$-' then return [Builtins.current_options, 2]
      when '$@' then return [@positional_params.join(' '), 2]
      when '$*' then return [Builtins.join_by_ifs(@positional_params), 2]
      end

      # Positional parameters $1-$9
      if str[pos + 1] =~ /[1-9]/
        return [@positional_params[str[pos + 1].to_i - 1] || '', 2]
      end

      # ${VAR} or ${VAR-default} form
      if str[pos + 1] == '{'
        end_brace = find_matching_brace(str, pos + 1)
        return [expand_parameter_expansion(str[pos + 2...end_brace]), end_brace - pos + 1] if end_brace
      end

      # $VAR form
      if str[pos + 1] =~ /[a-zA-Z_]/
        j = pos + 1
        j += 1 while j < str.length && str[j] =~ /[a-zA-Z0-9_]/
        return [fetch_var_with_nounset(str[pos + 1...j]), j - pos]
      end

      ['', 0]
    end

    # Find matching } for { at open_pos, handling nested braces
    def find_matching_brace(str, open_pos)
      depth = 1
      i = open_pos + 1
      while i < str.length && depth > 0
        case str[i]
        when '{' then depth += 1
        when '}' then depth -= 1
        when '\\' then i += 1
        end
        i += 1
      end
      depth == 0 ? i - 1 : nil
    end

    def expand_parameter_expansion(content)
      # ${#@}, ${#*}, ${#} - number of positional parameters
      return @positional_params.length.to_s if content.match?(/\A#[@*]?\z/)

      # ${#1}, ${##}, ${#?} - length of a positional or special parameter
      return __param_length($1) if content =~ /\A#(\d+|[#?$!-])\z/

      # ${N} - positional parameter (${10} and up need the braces); ${0} is $0
      if content.match?(/\A\d+\z/)
        n = content.to_i
        return n.zero? ? argv0 : (@positional_params[n - 1] || '')
      end

      # ${-} - current option flags
      return Builtins.current_options if content == '-'

      # ${@} and ${*} are the parameters themselves
      return @positional_params.join(' ') if content == '@'
      return Builtins.join_by_ifs(@positional_params) if content == '*'

      # ${+VAR} - zsh parameter-is-set test. Evaluates to '1' if the
      # variable is set (even to empty), '0' if not. starship and other
      # zsh prompt themers gate behaviour on this — e.g. precmd uses
      # `(( ${+STARSHIP_START_TIME} ))` to decide whether a preexec ran.
      return (Builtins.var_set?($1) ? '1' : '0') if content =~ /\A\+([a-zA-Z_][a-zA-Z0-9_]*)\z/

      # ${#arr[@]} or ${#arr[*]} - array length
      return __array_length($1) if content =~ /\A#([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\z/

      # ${!arr[@]} or ${!arr[*]} - array keys/indices
      return __array_keys($1, $2) if content =~ /\A!([a-zA-Z_][a-zA-Z0-9_]*)\[([@*])\]\z/

      # ${arr[@]} or ${arr[*]} - all array elements
      return __array_all($1, $2) if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([@*])\]\z/

      # ${arr[n]} - array element access
      return __array_element($1, $2) if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\]\z/

      # ${arr[@]:offset[:length]} / ${@:offset[:length]} - array slices
      if content =~ Codegen::SLICE_EXPANSION
        return __array_slice($1 || $3, $2 || $3, $4, $5)
      end

      # ${var:offset[:length]} - substring (offset/length are arithmetic)
      return __param_substring($1, $2, $3) if content =~ Codegen::SUBSTRING_EXPANSION

      # The operators below mirror Codegen#parse_parameter_expansion so a
      # builtin run directly by the REPL expands exactly like generated code.

      # ${var//pattern/replacement}, ${var/pattern/replacement}
      if content =~ %r{\A([a-zA-Z_][a-zA-Z0-9_]*(?:\[[^\]]+\])?|\d+|[@*])(//|/)((?:[^/]|\\.)+)/((?:[^/]|\\.)*)?\z}
        return __param_replace($1, $2, $3, $4 || '')
      end

      # ${var/pattern}, ${var//pattern} - delete matches
      if content =~ %r{\A([a-zA-Z_][a-zA-Z0-9_]*(?:\[[^\]]+\])?|\d+|[@*])(//|/)((?:[^/]|\\.)+)\z}
        return __param_replace($1, $2, $3, '')
      end

      # ${var^^}, ${var^}, ${var,,}, ${var,} - case modification
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*(?:\[[^\]]+\])?|\d+|[@*])(\^\^|\^|,,|,|~~|~)(?:([^}]*))?\z/
        return __param_case($1, $2, $3)
      end

      # ${var##pattern}, ${var%%pattern}, ${var#pattern}, ${var%pattern}
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*(?:\[[^\]]+\])?|\d+|[@*])(##|%%|#|%)(.+)\z/
        return __param_expand($1, $2, $3, expand_operand: true)
      end

      # ${var@operator} - transformations (Q, E, P, A, a, U, u, L, K)
      return __param_transform($1, $2) if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*(?:\[[^\]]+\])?|\d+|[@*])@([QEPAaUuLK])\z/

      # ${!prefix*} / ${!prefix@} - variable names with prefix
      if content =~ /\A!([a-zA-Z_][a-zA-Z0-9_]*)([*@])\z/
        names = __var_names_with_prefix($1)
        return $2 == '*' ? Builtins.join_by_ifs(names) : names.join(' ')
      end

      # ${!var} - indirect expansion
      return __param_indirect($1) if content =~ /\A!([a-zA-Z_][a-zA-Z0-9_]*)\z/

      # ${var:-default}, ${var-default}, etc.
      # Also handles positional parameters: ${1:-default}, ${10:-default}, etc.
      return __param_expand($1, $2, $3 || '', expand_operand: true) if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*(?:\[[^\]]+\])?|\d+|[@*#?$!-])(:-|:=|:\+|:\?|-|=|\+|\?)(.*)?\z/

      # ${#var} - length
      return __param_length($1) if content =~ /\A#([a-zA-Z_][a-zA-Z0-9_]*(?:\[[^\]]+\])?)\z/

      # Simple ${VAR}
      fetch_var_with_nounset(content)
    end

    def fetch_var_with_nounset(var_name)
      value = get_special_var_value(var_name)
      return value if value

      if Builtins.set_option?('u') && !Builtins.var_set?(var_name)
        $stderr.puts Builtins.format_error('unbound variable', command: var_name)
        raise NounsetError, "#{var_name}: unbound variable"
      end
      Builtins.get_var(var_name) || ''
    end

    # SECONDS - returns elapsed time since shell start (or last reset)
    def seconds
      (Time.now - @seconds_base).to_i
    end

    def reset_seconds(value = 0)
      @seconds_base = Time.now - value.to_i
    end

    # RANDOM - returns random number 0-32767
    def random
      @random_generator.rand(32768)
    end

    def seed_random(seed)
      @random_generator = Random.new(seed.to_i)
    end

    # COLUMNS - terminal width
    def terminal_columns
      IO.console&.winsize&.[](1) || ENV['COLUMNS']&.to_i || 80
    end

    # LINES - terminal height
    def terminal_lines
      IO.console&.winsize&.[](0) || ENV['LINES']&.to_i || 24
    end

    # checkwinsize: check window size after each command and update LINES/COLUMNS
    def check_window_size
      winsize = IO.console&.winsize
      return unless winsize

      lines, columns = winsize
      ENV['LINES'] = lines.to_s if lines && lines > 0
      ENV['COLUMNS'] = columns.to_s if columns && columns > 0
    end

    def extract_exit_status(result)
      case result
      when Command, Pipeline, Subshell, HeredocCommand
        ExitStatus.code_of(result.status)
      when ExitStatus
        result.exitstatus
      when Integer
        result
      else
        0
      end
    end

    # Strip comments from line (text after unquoted #)
    # Comments only start at # that's preceded by whitespace or at start of line
    # Respects quoting and ${...} parameter expansion
    def strip_comment(line)
      result = +''
      i = 0
      in_single_quotes = false
      in_double_quotes = false
      brace_depth = 0

      while i < line.length
        char = line[i]

        if char == '\\' && !in_single_quotes && i + 1 < line.length
          result << char << line[i + 1]
          i += 2
        elsif char == "'" && !in_double_quotes && brace_depth == 0
          in_single_quotes = !in_single_quotes
          result << char
          i += 1
        elsif char == '"' && !in_single_quotes && brace_depth == 0
          in_double_quotes = !in_double_quotes
          result << char
          i += 1
        elsif char == '$' && line[i + 1] == '{' && !in_single_quotes
          result << char << '{'
          brace_depth += 1
          i += 2
        elsif char == '{' && brace_depth > 0
          brace_depth += 1
          result << char
          i += 1
        elsif char == '}' && brace_depth > 0
          brace_depth -= 1
          result << char
          i += 1
        elsif char == '#' && !in_single_quotes && !in_double_quotes && brace_depth == 0
          prev_char = i > 0 ? result[-1] : nil
          if prev_char.nil? || prev_char =~ /\s/
            # `#` starts a comment to end of LINE (not end of input). For a
            # multi-line input like `eval "$(starship init zsh)"` the first
            # `# …` would otherwise eat the entire rest of the script.
            nl = line.index("\n", i)
            i = nl || line.length
          else
            result << char
            i += 1
          end
        else
          result << char
          i += 1
        end
      end

      result.rstrip
    end

    # Expand ~ and ~user (but not inside single quotes)
    # Also handles ~+ (PWD), ~- (OLDPWD), and named directories
    def expand_tilde(line)
      result = +''
      i = 0
      in_single_quotes = false
      in_double_quotes = false

      while i < line.length
        char = line[i]

        if char == "'" && !in_double_quotes
          in_single_quotes = !in_single_quotes
          result << char
          i += 1
        elsif char == '"' && !in_single_quotes
          in_double_quotes = !in_double_quotes
          result << char
          i += 1
        elsif char == '~' && !in_single_quotes && !in_double_quotes
          expanded, consumed = expand_tilde_at(line, i, result)
          result << expanded
          i += consumed
        else
          result << char
          i += 1
        end
      end

      result
    end

    # Alias for internal use - delegates to get_special_var_value
    def get_special_var(var_name)
      get_special_var_value(var_name)
    end

    # Returns RUBISH_VERSINFO array similar to BASH_VERSINFO
    # [0] major, [1] minor, [2] patch, [3] extra, [4] release status, [5] machine type
    def rubish_versinfo
      parts = Rubish::VERSION.split('.')
      [parts[0] || '0', parts[1] || '0', parts[2] || '0', '', 'release', RUBY_PLATFORM]
    end

    # Returns OS type from RUBY_PLATFORM (e.g., "darwin23", "linux-gnu")
    def ostype
      parts = RUBY_PLATFORM.split('-', 2)
      parts[1] || RUBY_PLATFORM
    end

    # Returns host/machine type from RUBY_PLATFORM (e.g., "arm64", "x86_64")
    def hosttype
      RUBY_PLATFORM.split('-').first
    end

    # Returns the value from the system's monotonic clock in seconds
    # The monotonic clock is not affected by system time changes
    def monoseconds
      defined?(Process::CLOCK_MONOTONIC) ? Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i : Time.now.to_i
    end

    # Returns the same value as $0 (the shell or script name)
    # RUBISH_ARGV0 overrides @script_name if set (even if empty)
    def argv0
      Builtins.var_set?('RUBISH_ARGV0') ? Builtins.get_var('RUBISH_ARGV0') : @script_name
    end

    # Returns the full pathname used to invoke rubish (like BASH in bash)
    def rubish_path
      @rubish_path ||= begin
        if $PROGRAM_NAME && File.exist?($PROGRAM_NAME)
          File.expand_path($PROGRAM_NAME)
        else
          exe_path = File.expand_path('../../exe/rubish', __dir__)
          if File.exist?(exe_path)
            exe_path
          else
            path_dirs = (ENV['PATH'] || '').split(':')
            path_dirs.map { |d| File.join(d, 'rubish') }.find { |p| File.exist?(p) } || $PROGRAM_NAME || 'rubish'
          end
        end
      end
    end

    # Remove suffix matching pattern from value
    # For shortest (%), find rightmost match start position
    # For longest (%%), find leftmost match start position
    def remove_suffix(value, pattern, mode)
      regex = pattern_to_regex(pattern, :full, mode)

      if mode == :shortest
        (value.length - 1).downto(0) do |i|
          return value[0...i] if regex.match?(value[i..])
        end
      else
        (0...value.length).each do |i|
          return value[0...i] if regex.match?(value[i..])
        end
      end
      value
    end

    # Convert shell glob pattern to regex
    # * -> .* or .*? (depending on greedy mode)
    # ? -> .
    # [...] -> [...] (with [! converted to [^)
    # position: :prefix, :suffix, :full, or :any for anchoring
    # An extended pattern (`+( )`, `@(jpg|jpeg)`) for the # % / operators:
    # the anchored regex that extglob_to_regex builds, with its quantifiers
    # made reluctant for the shortest-match operators
    def extglob_pattern_to_regex(pattern, position, greedy)
      regex_str = extglob_to_regex(pattern).source.delete_prefix('\A').delete_suffix('\z')
      regex_str = regex_str.gsub(/([).\]])([*+?])(?!\?)/) { "#{$1}#{$2}?" } if greedy == :shortest

      case position
      when :prefix then Regexp.new("\\A#{regex_str}")
      when :suffix then Regexp.new("#{regex_str}\\z")
      when :full then Regexp.new("\\A#{regex_str}\\z")
      else Regexp.new(regex_str)
      end
    end

    def pattern_to_regex(pattern, position, greedy)
      if Builtins.shopt_enabled?('extglob') && pattern.match?(/[?*+@!]\(/)
        return extglob_pattern_to_regex(pattern, position, greedy)
      end

      regex_str = +''
      i = 0
      while i < pattern.length
        char = pattern[i]
        case char
        when '*' then regex_str << (greedy == :longest ? '.*' : '.*?')
        when '?' then regex_str << '.'
        when '\\'
          # Backslash quotes the next pattern character (`\"`, `\*`, `\.`)
          i += 1
          regex_str << Regexp.escape(pattern[i] || '\\')
        when '['
          j = i + 1
          j += 1 if j < pattern.length && pattern[j] == '!'
          j += 1 if j < pattern.length && pattern[j] == ']'
          while j < pattern.length && pattern[j] != ']'
            # A POSIX class `[:space:]` inside the bracket keeps its own `]`
            if pattern[j] == '[' && pattern[j + 1] == ':' && (close = pattern.index(':]', j + 2))
              j = close + 2
            else
              j += 1
            end
          end
          if j < pattern.length
            bracket = pattern[i..j].sub('[!', '[^')
            regex_str << bracket
            i = j
          else
            regex_str << Regexp.escape(char)
          end
        else
          regex_str << Regexp.escape(char)
        end
        i += 1
      end

      case position
      when :prefix then Regexp.new("\\A#{regex_str}")
      when :suffix then Regexp.new("#{regex_str}\\z")
      when :full then Regexp.new("\\A#{regex_str}\\z")
      else Regexp.new(regex_str)
      end
    end

    private

    # Handle $'...' and '...' and "..." quoting
    # Expand a plain double-quoted word containing "${arr[@]}" into one word
    # per element, with any surrounding text attached to the first and last
    # element. Returns nil for any other word.
    def expand_quoted_array_word(value)
      return nil unless value.length >= 2 && value.start_with?('"') && value.end_with?('"')
      return nil if WordSegments.multi_segment?(value)

      pieces = WordSegments.split_quoted_array_word(value[1...-1])
      return nil unless pieces

      expanded = pieces.map do |type, content, spec|
        case type
        when :array then __array_values(content)
        when :keys then __array_key_list(content)
        when :prefix_names then __var_names_with_prefix(content)
        when :slice
          offset, length = spec.split(':', 2)
          __array_slice_values(content, offset, length)
        when :op then __param_element_words(content, spec)
        else expand_string_content(content, quoted: true)
        end
      end
      __quoted_array_words(expanded)
    end

    def expand_quoted_string(value)
      if value.start_with?("$'") && value.end_with?("'")
        Builtins.process_escape_sequences(value[2...-1])
      elsif WordSegments.multi_segment?(value)
        expand_multi_segment_word(value)
      elsif value.start_with?("'") && value.end_with?("'")
        value[1...-1]
      elsif value.start_with?('"') && value.end_with?('"')
        expand_string_content(value[1...-1], quoted: true)
      else
        yield  # Return nil or call the block for unquoted handling
      end
    end

    def expand_multi_segment_word(str)
      parts = []
      WordSegments.each_segment(str) do |type, content|
        parts << case type
                 when :single then content
                 when :ansi_c then Builtins.process_escape_sequences(content)
                 when :double then expand_string_content(content, quoted: true)
                 when :bare then expand_string_content(content)
                 end
      end
      parts.join
    end

    # Handle array assignment: arr=(a b c) or arr+=(d e) or map=([k]=v ...)
    def handle_array_assignment(var_name, elements_str, is_append)
      if Builtins.assoc_array?(var_name)
        pairs = parse_assoc_array_elements(elements_str)
        if is_append
          pairs.each { |k, v| Builtins.set_assoc_element(var_name, k, v) }
        else
          Builtins.set_assoc_array(var_name, pairs)
        end
      else
        elements = parse_array_elements(elements_str)
        if var_name == 'COMPREPLY'
          if is_append
            Builtins.compreply.concat(elements)
          else
            Builtins.compreply = elements.dup
          end
          Builtins.set_array('COMPREPLY', Builtins.compreply.dup)
        else
          Builtins.assign_array_literal(var_name, elements, append: is_append)
        end
      end
    end

    # Handle array element assignment: arr[0]=value or map[key]=value
    def handle_array_element_assignment(var_name, key, value)
      var_name = Builtins.array_name(var_name)
      expanded_key = expand_string_content(key)
      expanded_value = expand_assignment_value(value)
      expanded_value = eval_arithmetic_expr(expanded_value).to_s if Builtins.has_attribute?(var_name, :integer)

      # array_expand_once (bash 5.2+): when disabled, subscripts may be expanded again
      # assoc_expand_once (deprecated): same but only for associative arrays
      expand_once = Builtins.shopt_enabled?('array_expand_once') ||
                    (Builtins.assoc_array?(var_name) && Builtins.shopt_enabled?('assoc_expand_once'))
      if (Builtins.assoc_array?(var_name) || Builtins.indexed_array?(var_name)) && !expand_once
        expanded_key = expand_string_content(expanded_key) if expanded_key.include?('$')
      end

      if Builtins.assoc_array?(var_name)
        Builtins.set_assoc_element(var_name, expanded_key, expanded_value)
      elsif var_name == 'COMPREPLY'
        idx = expanded_key.to_i
        Builtins.compreply << nil while Builtins.compreply.length <= idx
        Builtins.compreply[idx] = expanded_value
        Builtins.set_array('COMPREPLY', Builtins.compreply.dup)
      else
        Builtins.set_array_element(var_name, expanded_key, expanded_value)
      end
    end

    # Handle scalar variable assignment: VAR=value
    # Includes special handling for SECONDS, RANDOM, LINENO, READLINE_*, etc.
    def handle_scalar_assignment(var_name, value)
      # Restricted mode: cannot modify restricted variables
      if Builtins.restricted_mode? && Builtins::RESTRICTED_VARIABLES.include?(var_name)
        $stderr.puts "rubish: #{var_name}: readonly variable"
        return
      end

      expanded_value = expand_assignment_value(value)

      case var_name
      when 'SECONDS' then reset_seconds(expanded_value.to_i)
      when 'RANDOM' then seed_random(expanded_value.to_i)
      when 'LINENO' then @lineno = expanded_value.to_i
      when 'BASH_ARGV0'
        unless @bash_argv0_unset
          Builtins.set_var('RUBISH_ARGV0', expanded_value)
          ENV['RUBISH_ARGV0'] = expanded_value
        else
          Builtins.set_var(var_name, expanded_value)
        end
      when 'BASH_COMPAT' then Builtins.set_bash_compat(expanded_value)
      when 'READLINE_LINE' then Builtins.readline_line = expanded_value
      when 'READLINE_POINT' then Builtins.readline_point = expanded_value.to_i
      when 'READLINE_MARK' then Builtins.readline_mark = expanded_value.to_i
      when *READONLY_SPECIAL_VARS
        # Read-only, silently ignore
      else
        # -i evaluates, -l / -u change case: the declared attributes apply
        expanded_value = Builtins.apply_attributes(var_name, expanded_value)
        Builtins.set_var_through_nameref(var_name, expanded_value)
      end

      Builtins.export_var(var_name) if Builtins.set_option?('a')
    end

    def find_matching_parens(str, start_pos, initial_depth)
      depth = initial_depth
      j = start_pos + initial_depth  # Skip the initial opening parens
      while j < str.length && depth > 0
        depth += 1 if str[j] == '('
        depth -= 1 if str[j] == ')'
        j += 1
      end
      depth == 0 ? j - 1 : nil
    end

    def extract_quoted_content(str, start_pos, quote_char)
      j = start_pos
      content = +''
      while j < str.length && str[j] != quote_char
        if str[j] == '\\' && j + 1 < str.length
          content << str[j, 2]
          j += 2
        else
          content << str[j]
          j += 1
        end
      end
      j < str.length && str[j] == quote_char ? [content, j] : [nil, nil]
    end

    def expand_tilde_at(line, i, result)
      prev_char = i > 0 ? line[i - 1] : nil
      next_char = i + 1 < line.length ? line[i + 1] : nil

      is_regex_op = prev_char == '=' && (next_char.nil? || next_char =~ /[\s\]]/)
      at_word_start = !is_regex_op && (prev_char.nil? || prev_char =~ /[\s"'=:]/)

      return ['~', 1] unless at_word_start

      case next_char
      when '+'
        # Defer to $PWD so it resolves at command-execution time, after any cd.
        return ['$PWD', 2] if line[i + 2].nil? || line[i + 2] =~ %r{[\s/]}
      when '-'
        # Defer to $OLDPWD; the `-` (no colon) default keeps bash's
        # semantics: literal `~-` only when OLDPWD is *unset*. An
        # explicitly-empty OLDPWD (`OLDPWD=; echo ~-`) expands to the
        # empty string, like bash. `${OLDPWD:-~-}` (colon-dash) would
        # incorrectly print `~-` for the empty case.
        return ['${OLDPWD-~-}', 2] if line[i + 2].nil? || line[i + 2] =~ %r{[\s/]}
      end

      j = i + 1
      j += 1 while j < line.length && line[j] =~ /[a-zA-Z0-9_-]/

      if j == i + 1
        [Dir.home, 1]
      else
        name = line[i + 1...j]
        named_dir = Builtins.get_named_directory(name)
        if named_dir
          [named_dir, j - i]
        else
          begin
            [Dir.home(name), j - i]
          rescue ArgumentError
            [line[i...j], j - i]
          end
        end
      end
    end

    def get_special_var_value(var_name)
      case var_name
      when 'SECONDS' then seconds.to_s
      when 'RANDOM' then random.to_s
      when 'LINENO' then @lineno.to_s
      when 'PPID' then Process.ppid.to_s
      when 'UID' then Process.uid.to_s
      when 'EUID' then Process.euid.to_s
      when 'GROUPS' then (Process.groups.first || '').to_s
      when 'HOSTNAME' then Socket.gethostname
      when 'RUBISHPID', 'BASHPID' then Process.pid.to_s
      when 'HISTCMD' then @command_number.to_s
      when 'EPOCHSECONDS' then Time.now.to_i.to_s
      when 'EPOCHREALTIME' then format('%.6f', Time.now.to_f)
      when 'SRANDOM' then SecureRandom.random_number(2**32).to_s
      when 'RUBISH_MONOSECONDS', 'BASH_MONOSECONDS' then monoseconds.to_s
      when 'BASH_ARGV0' then @bash_argv0_unset ? nil : argv0
      when 'RUBISH_VERSION', 'BASH_VERSION' then Rubish::VERSION
      when 'OSTYPE' then ostype
      when 'HOSTTYPE' then hosttype
      when 'MACHTYPE' then RUBY_PLATFORM
      when 'RUBISH_COMMAND', 'BASH_COMMAND' then @state.bash_command
      when 'FUNCNAME' then (@funcname_stack || []).first
      when 'RUBISH_SUBSHELL', 'BASH_SUBSHELL' then @subshell_level.to_s
      when 'COLUMNS' then terminal_columns.to_s
      when 'LINES' then terminal_lines.to_s
      when 'COMP_LINE' then Builtins.comp_line
      when 'COMP_POINT' then Builtins.comp_point.to_s
      when 'COMP_CWORD' then Builtins.comp_cword.to_s
      when 'COMP_TYPE' then Builtins.comp_type.to_s
      when 'COMP_KEY' then Builtins.comp_key.to_s
      when 'COMP_WORDBREAKS' then Builtins.comp_wordbreaks
      when 'SHELLOPTS' then Builtins.shellopts
      when 'RUBISHOPTS' then Builtins.rubishopts
      when 'BASHOPTS' then Builtins.bashopts
      when 'BASH_COMPAT' then Builtins.bash_compat
      when 'RUBISH_EXECUTION_STRING', 'BASH_EXECUTION_STRING' then ENV['RUBISH_EXECUTION_STRING'] || ''
      when 'RUBISH', 'BASH' then rubish_path
      when 'RUBISH_TRAPSIG', 'BASH_TRAPSIG' then Builtins.current_state.current_trapsig || ''
      when 'READLINE_LINE' then Builtins.readline_line
      when 'READLINE_POINT' then Builtins.readline_point.to_s
      when 'READLINE_MARK' then Builtins.readline_mark.to_s
      end
    end

    # Get parameter expansion info for a variable
    # Returns [value, is_set, is_null] tuple for use in parameter expansion operators
    def get_param_expand_info(var_name)
      # Check for special shell parameters first ($0-$9, $#, $@, $*, $?, $$, $!, $-)
      case var_name
      when /\A\d+\z/
        n = var_name.to_i
        if n == 0
          value = argv0
          [value, true, value.empty?]
        else
          value = @positional_params[n - 1]
          [value || '', n <= @positional_params.length, value.nil? || value.empty?]
        end
      when '#' then [@positional_params.length.to_s, true, false]
      when '@' then [@positional_params.join(' '), true, @positional_params.empty?]
      when '*' then [Builtins.join_by_ifs(@positional_params), true, @positional_params.empty?]
      when '?' then [@last_status.to_s, true, false]
      when '$' then [Process.pid.to_s, true, false]
      when '!'
        value = @last_bg_pid&.to_s || ''
        [value, !@last_bg_pid.nil?, @last_bg_pid.nil?]
      when '-' then [Builtins.current_options, true, Builtins.current_options.empty?]
      when /\A([a-zA-Z_][a-zA-Z0-9_]*)\[(.+)\]\z/
        # An element of a special array (${BASH_SOURCE[0]}), else a variable
        # the subscript-aware lookups handle
        values = get_special_array_values($1)
        if values.is_a?(Array)
          value = (values[safe_eval_index(expand_array_index($1, $2))] || '').to_s
          [value, true, value.empty?]
        else
          value = Builtins.get_var(var_name)
          [value, Builtins.var_set?(var_name), value.nil? || value.empty?]
        end
      else
        # Check special variables
        special_value = get_special_var_value(var_name)
        if special_value
          is_null = special_value.respond_to?(:empty?) ? special_value.empty? : false
          [special_value, true, is_null]
        else
          value = Builtins.get_var(var_name)
          [value, Builtins.var_set?(var_name), value.nil? || value.empty?]
        end
      end
    end

    def assign_default(var_name, operand)
      if Builtins.restricted_mode? && Builtins::RESTRICTED_VARIABLES.include?(var_name)
        $stderr.puts "rubish: #{var_name}: readonly variable"
        ''
      else
        Builtins.set_var(var_name, operand)
        operand
      end
    end

    # Build a proc for pattern replacement with & substitution
    # When patsub_replacement is enabled, & in replacement is replaced with the matched text
    # \& is a literal &
    def build_replacement_proc(replacement)
      return nil unless Builtins.shopt_enabled?('patsub_replacement') && replacement.include?('&')

      proc do |match|
        result = +''
        i = 0
        while i < replacement.length
          if replacement[i] == '\\' && i + 1 < replacement.length && replacement[i + 1] == '&'
            result << '&'
            i += 2
          elsif replacement[i] == '&'
            result << match
            i += 1
          else
            result << replacement[i]
            i += 1
          end
        end
        result
      end
    end

    def apply_case_transform(value, pattern, method, scope)
      if pattern.empty?
        scope == :all ? value.send(method) : value[0].send(method) + value[1..]
      else
        regex = pattern_to_regex(pattern, :any, :longest)
        if scope == :all
          value.gsub(regex) { |m| m.send(method) }
        else
          value[0].match?(regex) ? value[0].send(method) + value[1..] : value
        end
      end
    end

    # Expand array index/key based on array type
    # For associative arrays: expand as string (key lookup)
    # For indexed arrays: evaluate as arithmetic expression (allows bare variable names like ${arr[COMP_CWORD]})
    def expand_array_index(var_name, index)
      if Builtins.assoc_array?(var_name) || SPECIAL_ASSOC_ARRAYS.include?(var_name)
        expanded = expand_string_content(index)
        # assoc_expand_once: when disabled, subscripts may be expanded again
        unless Builtins.shopt_enabled?('assoc_expand_once')
          expanded = expand_string_content(expanded) if expanded.include?('$')
        end
        expanded
      else
        # Indexed array: evaluate subscript as arithmetic expression
        begin
          expanded = eval_arithmetic_expr(index).to_s
        rescue
          expanded = expand_string_content(index)
        end
        # array_expand_once (bash 5.2+): when disabled, subscripts may be expanded again
        unless Builtins.shopt_enabled?('array_expand_once')
          expanded = expand_string_content(expanded) if expanded.include?('$')
        end
        expanded
      end
    end

    def safe_eval_index(expanded_index)
      eval_arithmetic_expr(expanded_index).to_i
    rescue ArithmeticEvaluator::Error
      expanded_index.to_i
    end

    # Get values for special shell arrays (GROUPS, PIPESTATUS, FUNCNAME, etc.)
    # Returns Array for indexed arrays, :assoc for special associative arrays, nil otherwise
    def get_special_array_values(var_name)
      case var_name
      when 'GROUPS' then Process.groups
      when 'RUBISH_VERSINFO', 'BASH_VERSINFO' then rubish_versinfo
      when 'PIPESTATUS', 'pipestatus' then @pipestatus
      when 'FUNCNAME' then @funcname_stack
      when 'RUBISH_LINENO', 'BASH_LINENO' then @rubish_lineno_stack
      when 'RUBISH_SOURCE', 'BASH_SOURCE'
        # Outside any function, the file being sourced is BASH_SOURCE[0]
        if @rubish_source_stack.empty? && @current_source_file && @current_source_file != 'main'
          [@current_source_file]
        else
          @rubish_source_stack
        end
      when 'RUBISH_ARGC', 'BASH_ARGC' then @rubish_argc_stack
      when 'RUBISH_ARGV', 'BASH_ARGV' then @rubish_argv_stack
      when 'DIRSTACK' then [Dir.pwd] + Builtins.current_state.dir_stack
      when 'COMP_WORDS' then Builtins.comp_words
      when 'COMPREPLY' then Builtins.compreply
      when 'RUBISH_REMATCH', 'BASH_REMATCH' then @state.arrays['RUBISH_REMATCH'] || []
      when 'RUBISH_ALIASES', 'BASH_ALIASES', 'RUBISH_CMDS', 'BASH_CMDS' then :assoc
      end
    end

    def get_special_assoc_value(var_name, key)
      case var_name
      when 'RUBISH_ALIASES', 'BASH_ALIASES' then (Builtins.current_state.aliases[key] || '').to_s
      when 'RUBISH_CMDS', 'BASH_CMDS' then (Builtins.current_state.command_hash[key] || '').to_s
      else ''
      end
    end

    def get_special_assoc_all_values(var_name)
      case var_name
      when 'RUBISH_ALIASES', 'BASH_ALIASES' then Builtins.current_state.aliases.values
      when 'RUBISH_CMDS', 'BASH_CMDS' then Builtins.current_state.command_hash.values
      else []
      end
    end

    def get_special_assoc_length(var_name)
      case var_name
      when 'RUBISH_ALIASES', 'BASH_ALIASES' then Builtins.current_state.aliases.length
      when 'RUBISH_CMDS', 'BASH_CMDS' then Builtins.current_state.command_hash.length
      else 0
      end
    end

    def get_special_assoc_keys(var_name)
      case var_name
      when 'RUBISH_ALIASES', 'BASH_ALIASES' then Builtins.current_state.aliases.keys
      when 'RUBISH_CMDS', 'BASH_CMDS' then Builtins.current_state.command_hash.keys
      else []
      end
    end
  end
end
