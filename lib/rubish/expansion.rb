# frozen_string_literal: true

module Rubish
  # String, variable, and parameter expansion for the shell REPL
  # Handles variable expansion, command substitution, tilde expansion, parameter expansion, etc.
  module Expansion
    # Special associative arrays that use string keys (not registered with assoc_array?)
    SPECIAL_ASSOC_ARRAYS = %w[RUBISH_ALIASES BASH_ALIASES RUBISH_CMDS BASH_CMDS].freeze

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
        start_idx = prefix.length - 1  # position of (
        depth = 1
        i = prefix.length
        while i < remaining.length && depth > 0
          case remaining[i]
          when '('
            depth += 1
          when ')'
            depth -= 1
          end
          i += 1
        end

        return nil if depth != 0  # Unmatched parens

        assignment = remaining[0...i]
        assignments << assignment
        remaining = remaining[i..].strip
      end

      # If there's remaining content that's not whitespace, this isn't a pure array assignment line
      return nil unless remaining.empty?

      assignments.empty? ? nil : assignments
    end

    def handle_bare_assignments(assignments)
      assignments.each do |assignment|
        if assignment =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\+?=\((.*)\)\z/m
          # Array assignment: arr=(a b c) or arr+=(d e) or map=([k]=v ...)
          var_name = $1
          elements_str = $2
          is_append = assignment.include?('+=')

          # Check if this is associative array syntax: ([key]=value ...)
          if elements_str =~ /\A\s*\[/ || Builtins.assoc_array?(var_name)
            # Associative array
            pairs = parse_assoc_array_elements(elements_str)
            if is_append
              pairs.each { |k, v| Builtins.set_assoc_element(var_name, k, v) }
            else
              Builtins.set_assoc_array(var_name, pairs)
            end
          else
            # Indexed array
            elements = parse_array_elements(elements_str)
            # Special handling for COMPREPLY array - update both class variable and array
            # Note: Use dup to avoid sharing array references between @compreply and @arrays['COMPREPLY']
            if var_name == 'COMPREPLY'
              if is_append
                Builtins.compreply.concat(elements)
                # Don't double-append; just sync from compreply
                Builtins.set_array('COMPREPLY', Builtins.compreply.dup)
              else
                Builtins.compreply = elements.dup
                Builtins.set_array('COMPREPLY', elements.dup)
              end
            elsif is_append
              Builtins.array_append(var_name, elements)
            else
              Builtins.set_array(var_name, elements)
            end
          end
        elsif assignment =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\]=(.*)\z/
          # Array element assignment: arr[0]=value or map[key]=value
          var_name = $1
          key = $2
          value = $3
          expanded_key = expand_string_content(key)
          expanded_value = expand_assignment_value(value)

          # array_expand_once (bash 5.2+): when disabled, subscripts may be expanded again
          # assoc_expand_once (deprecated): same but only for associative arrays
          expand_once = Builtins.shopt_enabled?('array_expand_once') ||
                        (Builtins.assoc_array?(var_name) && Builtins.shopt_enabled?('assoc_expand_once'))
          if (Builtins.assoc_array?(var_name) || Builtins.indexed_array?(var_name)) && !expand_once
            if expanded_key.include?('$')
              expanded_key = expand_string_content(expanded_key)
            end
          end

          if Builtins.assoc_array?(var_name)
            # Associative array element
            Builtins.set_assoc_element(var_name, expanded_key, expanded_value)
          elsif var_name == 'COMPREPLY'
            # Special handling for COMPREPLY array element - update both class variable and array
            idx = expanded_key.to_i
            # Ensure compreply array is large enough
            while Builtins.compreply.length <= idx
              Builtins.compreply << nil
            end
            Builtins.compreply[idx] = expanded_value
            # Sync to @arrays['COMPREPLY']
            Builtins.set_array('COMPREPLY', Builtins.compreply.dup)
          else
            # Indexed array element
            Builtins.set_array_element(var_name, expanded_key, expanded_value)
          end
        elsif assignment =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)=(.*)\z/m
          # Regular variable assignment (use /m to match newlines in value)
          var_name = $1
          value = $2
          # Restricted mode: cannot modify restricted variables
          if Builtins.restricted_mode? && Builtins::RESTRICTED_VARIABLES.include?(var_name)
            $stderr.puts "rubish: #{var_name}: readonly variable"
            next
          end
          expanded_value = expand_assignment_value(value)
          # Special handling for SECONDS, RANDOM, LINENO, PPID, UID, and EUID
          if var_name == 'SECONDS'
            reset_seconds(expanded_value.to_i)
          elsif var_name == 'RANDOM'
            seed_random(expanded_value.to_i)
          elsif var_name == 'LINENO'
            @lineno = expanded_value.to_i
          elsif var_name == 'BASH_ARGV0'
            # BASH_ARGV0: Assigning a value also sets $0 to the same value
            # Unless it has been unset, in which case it loses special properties
            unless @bash_argv0_unset
              # Store in both shell_vars and ENV so child processes can inherit
              Builtins.set_var('RUBISH_ARGV0', expanded_value)
              ENV['RUBISH_ARGV0'] = expanded_value
            else
              Builtins.set_var(var_name, expanded_value)
            end
          elsif var_name == 'BASH_COMPAT'
            # BASH_COMPAT: Set shell compatibility level
            # Accepts "5.1", "51", or empty to clear
            Builtins.set_bash_compat(expanded_value)
          elsif var_name == 'READLINE_LINE'
            # READLINE_LINE: Set readline buffer (used in bind -x commands)
            Builtins.readline_line = expanded_value
          elsif var_name == 'READLINE_POINT'
            # READLINE_POINT: Set cursor position in readline buffer
            Builtins.readline_point = expanded_value.to_i
          elsif var_name == 'READLINE_MARK'
            # READLINE_MARK: Set mark position in readline buffer
            Builtins.readline_mark = expanded_value.to_i
          elsif var_name == 'PPID' || var_name == 'UID' || var_name == 'EUID' || var_name == 'GROUPS' || var_name == 'HOSTNAME' || var_name == 'RUBISHPID' || var_name == 'BASHPID' || var_name == 'HISTCMD' || var_name == 'EPOCHSECONDS' || var_name == 'EPOCHREALTIME' || var_name == 'SRANDOM' || var_name == 'RUBISH_MONOSECONDS' || var_name == 'BASH_MONOSECONDS' || var_name == 'RUBISH_VERSION' || var_name == 'BASH_VERSION' || var_name == 'RUBISH_VERSINFO' || var_name == 'BASH_VERSINFO' || var_name == 'OSTYPE' || var_name == 'HOSTTYPE' || var_name == 'MACHTYPE' || var_name == 'PIPESTATUS' || var_name == 'RUBISH_COMMAND' || var_name == 'BASH_COMMAND' || var_name == 'FUNCNAME' || var_name == 'RUBISH_LINENO' || var_name == 'BASH_LINENO' || var_name == 'RUBISH_SOURCE' || var_name == 'BASH_SOURCE' || var_name == 'RUBISH_ARGC' || var_name == 'BASH_ARGC' || var_name == 'RUBISH_ARGV' || var_name == 'BASH_ARGV' || var_name == 'RUBISH_SUBSHELL' || var_name == 'BASH_SUBSHELL' || var_name == 'DIRSTACK' || var_name == 'COLUMNS' || var_name == 'LINES' || var_name == 'RUBISH_ALIASES' || var_name == 'BASH_ALIASES' || var_name == 'RUBISH_CMDS' || var_name == 'BASH_CMDS' || var_name == 'COMP_CWORD' || var_name == 'COMP_LINE' || var_name == 'COMP_POINT' || var_name == 'COMP_TYPE' || var_name == 'COMP_KEY' || var_name == 'COMP_WORDS' || var_name == 'RUBISH_EXECUTION_STRING' || var_name == 'BASH_EXECUTION_STRING' || var_name == 'RUBISH_REMATCH' || var_name == 'BASH_REMATCH' || var_name == 'RUBISH' || var_name == 'BASH' || var_name == 'RUBISH_TRAPSIG' || var_name == 'BASH_TRAPSIG'
            # These variables are read-only, silently ignore assignment
          else
            Builtins.set_var(var_name, expanded_value)
          end
          # allexport: mark variable as exported when set -a is enabled
          Builtins.export_var(var_name) if Builtins.set_option?('a')
        end
      end
    end

    def parse_assoc_array_elements(str)
      # Parse associative array elements: [key1]=value1 [key2]=value2
      pairs = {}
      # Match [key]=value patterns
      str.scan(/\[([^\]]+)\]=(\S+|'[^']*'|"[^"]*")/) do |key, value|
        expanded_key = expand_string_content(key)
        expanded_value = expand_assignment_value(value)
        pairs[expanded_key] = expanded_value
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
      i = 0

      while i < str.length
        char = str[i]

        if char == "'" && !in_double_quote && paren_depth == 0
          in_single_quote = !in_single_quote
          current << char
        elsif char == '"' && !in_single_quote && paren_depth == 0
          in_double_quote = !in_double_quote
          current << char
        elsif char == '(' && !in_single_quote && !in_double_quote
          paren_depth += 1
          current << char
        elsif char == ')' && !in_single_quote && !in_double_quote && paren_depth > 0
          paren_depth -= 1
          current << char
        elsif char =~ /\s/ && !in_single_quote && !in_double_quote && paren_depth == 0
          unless current.empty?
            elements.concat(expand_array_element(current))
            current = +''
          end
        else
          current << char
        end
        i += 1
      end

      elements.concat(expand_array_element(current)) unless current.empty?
      elements
    end

    # Expand an array element, with word splitting for command substitution
    def expand_array_element(value)
      return [''] if value.nil? || value.empty?

      # Check if this is purely a command substitution: $(cmd) or `cmd`
      if value =~ /\A\$\(.*\)\z/m || value =~ /\A`.*`\z/m
        # Pure command substitution - expand and word-split the result
        expanded = expand_string_content(value)
        # Word-split on IFS (default: space, tab, newline)
        ifs = ENV['IFS'] || " \t\n"
        return expanded.split(/[#{Regexp.escape(ifs)}]+/)
      end

      # Not a pure command substitution - expand normally (returns single element)
      [expand_assignment_value(value)]
    end

    def expand_assignment_value(value)
      return '' if value.nil? || value.empty?

      # $'...' ANSI-C quoting: process escape sequences
      if value.start_with?("$'") && value.end_with?("'")
        return Builtins.process_escape_sequences(value[2...-1])
      end

      # Handle quoted strings
      if value.start_with?("'") && value.end_with?("'")
        return value[1...-1]
      end

      if value.start_with?('"') && value.end_with?('"')
        return expand_string_content(value[1...-1])
      end

      # Expand variables and command substitution in unquoted values
      expand_string_content(value)
    end

    def expand_single_arg_with_brace_and_glob(arg)
      return [arg] unless arg.is_a?(String)

      # $'...' ANSI-C quoting: process escape sequences
      if arg.start_with?("$'") && arg.end_with?("'")
        return [Builtins.process_escape_sequences(arg[2...-1])]
      end

      # Single-quoted strings: no expansion, strip quotes
      if arg.start_with?("'") && arg.end_with?("'")
        return [arg[1...-1]]
      end

      # Double-quoted strings: strip quotes, expand variables, no glob/brace
      if arg.start_with?('"') && arg.end_with?('"')
        return [expand_string_content(arg[1...-1])]
      end

      # Brace expansion first (before variable expansion in shell, but we do it after for simplicity)
      # Expand braces first (only if braceexpand option is enabled)
      brace_expanded = if Builtins.set_option?('B') && arg.include?('{') && !arg.start_with?('$')
                         expand_braces(arg)
                       else
                         [arg]
                       end

      # Then expand variables and globs on each result
      brace_expanded.flat_map do |item|
        expanded = expand_string_content(item)
        # In bash, when an unquoted variable expands to empty, it's removed from
        # the argument list (word splitting removes empty words). This is different
        # from "$var" which preserves the empty string as an argument.
        # Since we're in the unquoted branch here, remove empty expansions.
        next [] if expanded.empty?

        # Then expand globs if present
        if expanded.match?(/[*?\[]/)
          __glob(expanded)
        else
          [expanded]
        end
      end
    end

    def expand_single_arg_with_glob(arg)
      return [arg] unless arg.is_a?(String)

      # $'...' ANSI-C quoting: process escape sequences
      if arg.start_with?("$'") && arg.end_with?("'")
        return [Builtins.process_escape_sequences(arg[2...-1])]
      end

      # Single-quoted strings: no expansion, strip quotes
      if arg.start_with?("'") && arg.end_with?("'")
        return [arg[1...-1]]
      end

      # Double-quoted strings: strip quotes, expand variables, no glob
      if arg.start_with?('"') && arg.end_with?('"')
        return [expand_string_content(arg[1...-1])]
      end

      # Unquoted: expand variables first
      expanded = expand_string_content(arg)

      # In bash, when an unquoted variable expands to empty, it's removed from
      # the argument list (word splitting removes empty words).
      return [] if expanded.empty?

      # Then expand globs if present
      if expanded.match?(/[*?\[]/)
        __glob(expanded)
      else
        [expanded]
      end
    end

    def expand_single_arg(arg)
      return arg unless arg.is_a?(String)

      # $'...' ANSI-C quoting: process escape sequences
      if arg.start_with?("$'") && arg.end_with?("'")
        return Builtins.process_escape_sequences(arg[2...-1])
      end

      # Single-quoted strings: no expansion, strip quotes
      if arg.start_with?("'") && arg.end_with?("'")
        return arg[1...-1]
      end

      # Double-quoted strings: strip quotes, expand variables
      if arg.start_with?('"') && arg.end_with?('"')
        return expand_string_content(arg[1...-1])
      end

      # Unquoted: expand variables
      expand_string_content(arg)
    end

    def expand_string_content(str)
      result = +''
      i = 0

      while i < str.length
        char = str[i]

        if char == '\\'
          # Escape sequence - only consume backslash for special characters
          # In double quotes, only \$, \`, \", \\, and \newline are special
          next_char = str[i + 1]
          if next_char && '$`"\\'.include?(next_char)
            result << next_char
            i += 2
          else
            # Keep the backslash for other characters (like \C-a in bind)
            result << char
            i += 1
          end
        elsif char == '`'
          # Backtick command substitution
          expanded, consumed = expand_backtick_at(str, i)
          if consumed > 0
            result << expanded
            i += consumed
          else
            result << char
            i += 1
          end
        elsif char == '$'
          expanded, consumed = expand_variable_at(str, i)
          if consumed > 0
            result << expanded
            i += consumed
          else
            result << char
            i += 1
          end
        elsif char == '"'
          # Quote removal: skip double quotes (they're used for grouping, not literal)
          i += 1
        else
          result << char
          i += 1
        end
      end

      result
    end

    def expand_extquote(str)
      # Process $'...' (ANSI-C quoting) and $"..." (locale translation) in a string
      # Used by extquote shopt option for parameter expansion operands
      result = +''
      i = 0

      while i < str.length
        if str[i] == '$' && i + 1 < str.length
          if str[i + 1] == "'"
            # $'...' - ANSI-C quoting
            j = i + 2
            content = +''
            while j < str.length && str[j] != "'"
              if str[j] == '\\' && j + 1 < str.length
                # Handle escape sequences
                content << str[j, 2]
                j += 2
              else
                content << str[j]
                j += 1
              end
            end
            if j < str.length && str[j] == "'"
              # Process escape sequences
              result << Builtins.process_escape_sequences(content)
              i = j + 1
              next
            end
          elsif str[i + 1] == '"'
            # $"..." - locale translation
            j = i + 2
            content = +''
            while j < str.length && str[j] != '"'
              if str[j] == '\\' && j + 1 < str.length
                content << str[j, 2]
                j += 2
              else
                content << str[j]
                j += 1
              end
            end
            if j < str.length && str[j] == '"'
              # Expand variables in content first, then translate
              expanded_content = expand_string_content(content)
              result << __translate(expanded_content)
              i = j + 1
              next
            end
          end
        end
        result << str[i]
        i += 1
      end

      result
    end

    def expand_backtick_at(str, pos)
      return ['', 0] unless str[pos] == '`'

      # Find matching closing backtick
      j = pos + 1
      while j < str.length
        if str[j] == '\\'
          # Skip escaped character
          j += 2
        elsif str[j] == '`'
          # Found closing backtick
          cmd = str[pos + 1...j]
          output = __run_subst(cmd)
          return [output, j - pos + 1]
        else
          j += 1
        end
      end

      ['', 0]  # Unclosed backtick
    end

    def expand_variable_at(str, pos)
      return ['', 0] unless str[pos] == '$'

      # Arithmetic expansion $((...))
      if str[pos + 1] == '(' && str[pos + 2] == '('
        depth = 2
        j = pos + 3
        while j < str.length && depth > 0
          if str[j] == '('
            depth += 1
          elsif str[j] == ')'
            depth -= 1
          end
          j += 1
        end
        if depth == 0
          expr = str[pos + 3...j - 2]
          return [__arith(expr), j - pos]
        end
        return ['', 0]
      end

      # Command substitution $(...)
      if str[pos + 1] == '('
        depth = 1
        j = pos + 2
        while j < str.length && depth > 0
          j += 1 and next if str[j] == '('  && (depth += 1)
          j += 1 and next if str[j] == ')'  && (depth -= 1) > 0
          break if depth == 0
          j += 1
        end
        if depth == 0
          cmd = str[pos + 2...j]
          return [__run_subst(cmd), j - pos + 1]
        end
        return ['', 0]
      end

      # Special variables
      two_char = str[pos, 2]
      case two_char
      when '$?'
        return [@last_status.to_s, 2]
      when '$$'
        return [Process.pid.to_s, 2]
      when '$!'
        return [@last_bg_pid ? @last_bg_pid.to_s : '', 2]
      when '$0'
        # RUBISH_ARGV0 overrides $0 if set (even if empty)
        return [__bash_argv0, 2]
      when '$#'
        return [@positional_params.length.to_s, 2]
      when '$@'
        return [@positional_params.join(' '), 2]
      when '$*'
        # $* joins with first character of IFS
        return [Builtins.join_by_ifs(@positional_params), 2]
      end

      if str[pos + 1] =~ /[1-9]/
        n = str[pos + 1].to_i
        return [@positional_params[n - 1] || '', 2]
      end

      # ${VAR} or ${VAR-default} form
      if str[pos + 1] == '{'
        end_brace = find_matching_brace(str, pos + 1)
        if end_brace
          content = str[pos + 2...end_brace]
          return [expand_parameter_expansion(content), end_brace - pos + 1]
        end
      end

      # $VAR form
      if str[pos + 1] =~ /[a-zA-Z_]/
        j = pos + 1
        j += 1 while j < str.length && str[j] =~ /[a-zA-Z0-9_]/
        var_name = str[pos + 1...j]
        return [fetch_var_with_nounset(var_name), j - pos]
      end

      ['', 0]
    end

    def find_matching_brace(str, open_pos)
      # Find matching } for { at open_pos, handling nested braces
      depth = 1
      i = open_pos + 1
      while i < str.length && depth > 0
        case str[i]
        when '{'
          depth += 1
        when '}'
          depth -= 1
        when '\\'
          i += 1  # Skip escaped character
        end
        i += 1
      end
      depth == 0 ? i - 1 : nil
    end

    def expand_parameter_expansion(content)
      # Handle ${#arr[@]} or ${#arr[*]} - array length
      if content =~ /\A#([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\z/
        var_name = $1
        return __array_length(var_name)
      end

      # Handle ${!arr[@]} or ${!arr[*]} - array keys/indices
      if content =~ /\A!([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\z/
        var_name = $1
        return __array_keys(var_name)
      end

      # Handle ${arr[@]} or ${arr[*]} - all array elements
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([@*])\]\z/
        var_name = $1
        mode = $2
        return __array_all(var_name, mode)
      end

      # Handle ${arr[n]} - array element access
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\]\z/
        var_name = $1
        index = $2
        return __array_element(var_name, index)
      end

      # Handle ${var:-default}, ${var-default}, ${var:=default}, ${var:+value}, ${var:?message}
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)(:-|:=|:\+|:\?|-|=|\+|\?)(.*)?\z/
        var_name = $1
        operator = $2
        operand = $3 || ''
        return __param_expand(var_name, operator, operand)
      end

      # Handle ${#var} - length
      if content =~ /\A#([a-zA-Z_][a-zA-Z0-9_]*)\z/
        var_name = $1
        return __param_length(var_name)
      end

      # Simple ${VAR}
      fetch_var_with_nounset(content)
    end

    def fetch_var_with_nounset(var_name)
      # Special handling for SECONDS, RANDOM, LINENO, PPID, UID, EUID, GROUPS, HOSTNAME, RUBISHPID, BASHPID, HISTCMD, and EPOCHSECONDS
      return seconds.to_s if var_name == 'SECONDS'
      return random.to_s if var_name == 'RANDOM'
      return @lineno.to_s if var_name == 'LINENO'
      return Process.ppid.to_s if var_name == 'PPID'
      return Process.uid.to_s if var_name == 'UID'
      return Process.euid.to_s if var_name == 'EUID'
      return (Process.groups.first || '').to_s if var_name == 'GROUPS'
      return Socket.gethostname if var_name == 'HOSTNAME'
      return Process.pid.to_s if var_name == 'RUBISHPID'
      return Process.pid.to_s if var_name == 'BASHPID'
      return @command_number.to_s if var_name == 'HISTCMD'
      return Time.now.to_i.to_s if var_name == 'EPOCHSECONDS'
      return format('%.6f', Time.now.to_f) if var_name == 'EPOCHREALTIME'
      return SecureRandom.random_number(2**32).to_s if var_name == 'SRANDOM'
      return __bash_monoseconds.to_s if var_name == 'RUBISH_MONOSECONDS' || var_name == 'BASH_MONOSECONDS'
      return __bash_argv0 if var_name == 'BASH_ARGV0' && !@bash_argv0_unset
      return Rubish::VERSION if var_name == 'RUBISH_VERSION'
      return Rubish::VERSION if var_name == 'BASH_VERSION'
      return __ostype if var_name == 'OSTYPE'
      return __hosttype if var_name == 'HOSTTYPE'
      return RUBY_PLATFORM if var_name == 'MACHTYPE'
      return @rubish_command if var_name == 'RUBISH_COMMAND'
      return @rubish_command if var_name == 'BASH_COMMAND'
      return @subshell_level.to_s if var_name == 'RUBISH_SUBSHELL'
      return @subshell_level.to_s if var_name == 'BASH_SUBSHELL'
      return terminal_columns.to_s if var_name == 'COLUMNS'
      return terminal_lines.to_s if var_name == 'LINES'
      return Builtins.comp_line if var_name == 'COMP_LINE'
      return Builtins.comp_point.to_s if var_name == 'COMP_POINT'
      return Builtins.comp_cword.to_s if var_name == 'COMP_CWORD'
      return Builtins.comp_type.to_s if var_name == 'COMP_TYPE'
      return Builtins.comp_key.to_s if var_name == 'COMP_KEY'
      return Builtins.comp_wordbreaks if var_name == 'COMP_WORDBREAKS'
      return Builtins.shellopts if var_name == 'SHELLOPTS'
      return Builtins.rubishopts if var_name == 'RUBISHOPTS'
      return Builtins.bashopts if var_name == 'BASHOPTS'
      return Builtins.bash_compat if var_name == 'BASH_COMPAT'
      return ENV['RUBISH_EXECUTION_STRING'] || '' if var_name == 'RUBISH_EXECUTION_STRING' || var_name == 'BASH_EXECUTION_STRING'
      return __rubish_path if var_name == 'RUBISH' || var_name == 'BASH'
      return Builtins.current_trapsig || '' if var_name == 'RUBISH_TRAPSIG' || var_name == 'BASH_TRAPSIG'
      return Builtins.readline_line if var_name == 'READLINE_LINE'
      return Builtins.readline_point.to_s if var_name == 'READLINE_POINT'
      return Builtins.readline_mark.to_s if var_name == 'READLINE_MARK'

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

    # Reset SECONDS base time (when SECONDS is assigned)
    def reset_seconds(value = 0)
      @seconds_base = Time.now - value.to_i
    end

    # RANDOM - returns random number 0-32767
    def random
      @random_generator.rand(32768)
    end

    # Seed RANDOM generator
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
        result.status&.exitstatus || 0
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
    def strip_comment(line)
      result = +''
      i = 0
      in_single_quotes = false
      in_double_quotes = false
      brace_depth = 0

      while i < line.length
        char = line[i]

        if char == '\\' && !in_single_quotes && i + 1 < line.length
          # Escaped character - keep both
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
          # Start of ${...} parameter expansion - track brace depth
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
          # Comment starts at # preceded by whitespace or at start
          prev_char = i > 0 ? result[-1] : nil
          if prev_char.nil? || prev_char =~ /\s/
            # This is a comment - stop here
            break
          else
            # # is part of a word (like foo#bar), keep it
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

    def expand_tilde(line)
      # Expand ~ and ~user (but not inside single quotes)
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
        elsif char == '~' && !in_single_quotes
          # Check if ~ is at start of a word (preceded by space, start, or quotes)
          prev_char = i > 0 ? line[i - 1] : nil
          next_char = i + 1 < line.length ? line[i + 1] : nil
          # Don't expand ~ if it's part of =~ operator (= followed by ~ then space/end)
          # But DO expand ~ in assignments like FOO=~/path (= followed by ~/)
          is_regex_op = prev_char == '=' && (next_char.nil? || next_char =~ /[\s\]]/)
          at_word_start = !is_regex_op && (prev_char.nil? || prev_char =~ /[\s"'=:]/)

          if at_word_start
            next_char = line[i + 1]
            # Check for special ~+ (PWD) and ~- (OLDPWD)
            if next_char == '+' && (line[i + 2].nil? || line[i + 2] =~ %r{[\s/]})
              result << (ENV['PWD'] || Dir.pwd)
              i += 2
            elsif next_char == '-' && (line[i + 2].nil? || line[i + 2] =~ %r{[\s/]})
              if ENV['OLDPWD']
                result << ENV['OLDPWD']
              else
                result << '~-'  # Keep literal if OLDPWD not set
              end
              i += 2
            else
              # Look for username after ~
              j = i + 1
              j += 1 while j < line.length && line[j] =~ /[a-zA-Z0-9_-]/

              if j == i + 1
                # Just ~ or ~/path
                result << Dir.home
                i = j
              else
                # ~name - could be named directory or username
                name = line[i + 1...j]
                # First check for named directory (zsh hash -d)
                named_dir = Builtins.get_named_directory(name)
                if named_dir
                  result << named_dir
                  i = j
                else
                  # Try as ~username
                  begin
                    result << Dir.home(name)
                  rescue ArgumentError
                    # Unknown user, keep literal
                    result << line[i...j]
                  end
                  i = j
                end
              end
            end
          else
            result << char
            i += 1
          end
        else
          result << char
          i += 1
        end
      end

      result
    end

    def __run_subst(cmd)
      # Run command substitution within rubish itself (not external shell)
      # This allows user-defined functions to be available in $() substitution
      reader, writer = IO.pipe

      # Check inherit_errexit before forking - if disabled, child should not inherit errexit
      inherit_errexit = Builtins.shopt_enabled?('inherit_errexit')
      errexit_enabled = Builtins.set_option?('e')

      pid = fork do
        reader.close

        # Redirect stdout to the pipe using the constant STDOUT
        # This works even if $stdout has been redirected to a StringIO (for testing)
        STDOUT.reopen(writer)
        $stdout = STDOUT

        # Suppress stderr during completion to avoid spurious output on terminal
        # (e.g., "Usage: rbenv completions" when rbenv completions fails)
        if Builtins.in_completion_context?
          STDERR.reopen(File.open(File::NULL, 'w'))
          $stderr = STDERR
        end

        # Command substitution only inherits errexit when inherit_errexit is enabled
        # Without inherit_errexit, disable errexit in the subshell
        unless inherit_errexit
          Builtins.set_options['e'] = false
        end

        # Execute the command through rubish's full execution path
        # This properly handles errexit (set -e) with inherit_errexit
        begin
          exit_code = catch(:exit) do
            execute(cmd, skip_history_expansion: true)
            @last_status
          end
          exit(exit_code || 0)
        rescue => e
          $stderr.puts "rubish: #{e.message}" unless Builtins.in_completion_context?
          exit(1)
        end
      end

      writer.close
      output = reader.read.chomp
      reader.close

      Process.wait(pid)
      @last_status = $?.exitstatus || 0
      output
    end

    def __param_expand(var_name, operator, operand)
      # extquote: when enabled, process $'...' and $"..." quoting in the operand
      if Builtins.shopt_enabled?('extquote')
        operand = expand_extquote(operand)
      end

      # Parameter expansion operations
      # Special handling for SECONDS, RANDOM, LINENO, PPID, UID, EUID, and GROUPS
      if var_name == 'SECONDS'
        value = seconds.to_s
        is_set = true
        is_null = false
      elsif var_name == 'RANDOM'
        value = random.to_s
        is_set = true
        is_null = false
      elsif var_name == 'LINENO'
        value = @lineno.to_s
        is_set = true
        is_null = false
      elsif var_name == 'PPID'
        value = Process.ppid.to_s
        is_set = true
        is_null = false
      elsif var_name == 'UID'
        value = Process.uid.to_s
        is_set = true
        is_null = false
      elsif var_name == 'EUID'
        value = Process.euid.to_s
        is_set = true
        is_null = false
      elsif var_name == 'GROUPS'
        value = (Process.groups.first || '').to_s
        is_set = true
        is_null = Process.groups.empty?
      elsif var_name == 'HOSTNAME'
        value = Socket.gethostname
        is_set = true
        is_null = false
      elsif var_name == 'RUBISHPID'
        value = Process.pid.to_s
        is_set = true
        is_null = false
      elsif var_name == 'BASHPID'
        value = Process.pid.to_s
        is_set = true
        is_null = false
      elsif var_name == 'HISTCMD'
        value = @command_number.to_s
        is_set = true
        is_null = false
      elsif var_name == 'EPOCHSECONDS'
        value = Time.now.to_i.to_s
        is_set = true
        is_null = false
      elsif var_name == 'EPOCHREALTIME'
        value = format('%.6f', Time.now.to_f)
        is_set = true
        is_null = false
      elsif var_name == 'SRANDOM'
        value = SecureRandom.random_number(2**32).to_s
        is_set = true
        is_null = false
      elsif var_name == 'RUBISH_MONOSECONDS' || var_name == 'BASH_MONOSECONDS'
        value = __bash_monoseconds.to_s
        is_set = true
        is_null = false
      elsif var_name == 'BASH_ARGV0'
        if @bash_argv0_unset
          # After unset, BASH_ARGV0 is a regular variable
          value = Builtins.get_var(var_name)
          is_set = Builtins.var_set?(var_name)
          is_null = value.nil? || value.empty?
        else
          value = __bash_argv0
          is_set = true
          is_null = value.empty?
        end
      elsif var_name == 'RUBISH_VERSION'
        value = Rubish::VERSION
        is_set = true
        is_null = false
      elsif var_name == 'BASH_VERSION'
        value = Rubish::VERSION
        is_set = true
        is_null = false
      elsif var_name == 'OSTYPE'
        value = __ostype
        is_set = true
        is_null = false
      elsif var_name == 'HOSTTYPE'
        value = __hosttype
        is_set = true
        is_null = false
      elsif var_name == 'MACHTYPE'
        value = RUBY_PLATFORM
        is_set = true
        is_null = false
      elsif var_name == 'RUBISH_COMMAND' || var_name == 'BASH_COMMAND'
        value = @rubish_command
        is_set = true
        is_null = @rubish_command.empty?
      elsif var_name == 'RUBISH_SUBSHELL' || var_name == 'BASH_SUBSHELL'
        value = @subshell_level.to_s
        is_set = true
        is_null = false
      elsif var_name == 'COLUMNS'
        value = terminal_columns.to_s
        is_set = true
        is_null = false
      elsif var_name == 'LINES'
        value = terminal_lines.to_s
        is_set = true
        is_null = false
      elsif var_name == 'COMP_LINE'
        value = Builtins.comp_line
        is_set = true
        is_null = value.empty?
      elsif var_name == 'COMP_POINT'
        value = Builtins.comp_point.to_s
        is_set = true
        is_null = false
      elsif var_name == 'COMP_CWORD'
        value = Builtins.comp_cword.to_s
        is_set = true
        is_null = false
      elsif var_name == 'COMP_TYPE'
        value = Builtins.comp_type.to_s
        is_set = true
        is_null = false
      elsif var_name == 'COMP_KEY'
        value = Builtins.comp_key.to_s
        is_set = true
        is_null = false
      elsif var_name == 'COMP_WORDBREAKS'
        value = Builtins.comp_wordbreaks
        is_set = true
        is_null = false
      elsif var_name == 'BASH_COMPAT'
        value = Builtins.bash_compat
        is_set = true
        is_null = value.empty?
      elsif var_name == 'BASHOPTS'
        value = Builtins.bashopts
        is_set = true
        is_null = value.empty?
      elsif var_name == 'RUBISH_EXECUTION_STRING' || var_name == 'BASH_EXECUTION_STRING'
        value = ENV['RUBISH_EXECUTION_STRING'] || ''
        is_set = ENV.key?('RUBISH_EXECUTION_STRING')
        is_null = value.empty?
      elsif var_name == 'RUBISH' || var_name == 'BASH'
        value = __rubish_path
        is_set = true
        is_null = false
      elsif var_name == 'RUBISH_TRAPSIG' || var_name == 'BASH_TRAPSIG'
        value = Builtins.current_trapsig || ''
        is_set = true
        is_null = value.empty?
      elsif var_name == 'READLINE_LINE'
        value = Builtins.readline_line
        is_set = true
        is_null = value.empty?
      elsif var_name == 'READLINE_POINT'
        value = Builtins.readline_point.to_s
        is_set = true
        is_null = false
      elsif var_name == 'READLINE_MARK'
        value = Builtins.readline_mark.to_s
        is_set = true
        is_null = false
      elsif var_name =~ /\A\d+\z/
        # Positional parameters: $1, $2, etc.
        n = var_name.to_i
        if n == 0
          value = __bash_argv0
          is_set = true
          is_null = value.empty?
        else
          value = @positional_params[n - 1]
          is_set = n <= @positional_params.length
          is_null = value.nil? || value.empty?
          value ||= ''
        end
      elsif var_name == '#'
        value = @positional_params.length.to_s
        is_set = true
        is_null = false
      elsif var_name == '@'
        value = @positional_params.join(' ')
        is_set = true
        is_null = @positional_params.empty?
      elsif var_name == '*'
        value = Builtins.join_by_ifs(@positional_params)
        is_set = true
        is_null = @positional_params.empty?
      elsif var_name == '?'
        value = @last_status.to_s
        is_set = true
        is_null = false
      elsif var_name == '$'
        value = Process.pid.to_s
        is_set = true
        is_null = false
      elsif var_name == '!'
        value = @last_bg_pid ? @last_bg_pid.to_s : ''
        is_set = !@last_bg_pid.nil?
        is_null = @last_bg_pid.nil?
      elsif var_name == '-'
        value = Builtins.current_options
        is_set = true
        is_null = value.empty?
      else
        value = Builtins.get_var(var_name)
        is_set = Builtins.var_set?(var_name)
        is_null = value.nil? || value.empty?
      end

      case operator
      when ':-'
        # ${var:-default} - use default if unset or null
        is_null ? operand : value
      when '-'
        # ${var-default} - use default only if unset (null is fine)
        is_set ? value : operand
      when ':='
        # ${var:=default} - assign default if unset or null
        if is_null
          if Builtins.restricted_mode? && Builtins::RESTRICTED_VARIABLES.include?(var_name)
            $stderr.puts "rubish: #{var_name}: readonly variable"
            ''
          else
            Builtins.set_var(var_name, operand)
            operand
          end
        else
          value
        end
      when '='
        # ${var=default} - assign default only if unset
        if is_set
          value
        else
          if Builtins.restricted_mode? && Builtins::RESTRICTED_VARIABLES.include?(var_name)
            $stderr.puts "rubish: #{var_name}: readonly variable"
            ''
          else
            Builtins.set_var(var_name, operand)
            operand
          end
        end
      when ':+'
        # ${var:+value} - use value if set and non-null
        is_null ? '' : operand
      when '+'
        # ${var+value} - use value if set (even if null)
        is_set ? operand : ''
      when ':?'
        # ${var:?message} - error if unset or null
        if is_null
          msg = operand.empty? ? "#{var_name}: parameter null or not set" : operand
          raise msg
        end
        value
      when '?'
        # ${var?message} - error only if unset
        unless is_set
          msg = operand.empty? ? "#{var_name}: parameter not set" : operand
          raise msg
        end
        value || ''
      when '#'
        # ${var#pattern} - remove shortest prefix
        return '' if value.nil?
        pattern_to_regex(operand, :prefix, :shortest).match(value) do |m|
          value[m.end(0)..]
        end || value
      when '##'
        # ${var##pattern} - remove longest prefix
        return '' if value.nil?
        pattern_to_regex(operand, :prefix, :longest).match(value) do |m|
          value[m.end(0)..]
        end || value
      when '%'
        # ${var%pattern} - remove shortest suffix
        return '' if value.nil?
        remove_suffix(value, operand, :shortest)
      when '%%'
        # ${var%%pattern} - remove longest suffix
        return '' if value.nil?
        remove_suffix(value, operand, :longest)
      else
        value || ''
      end
    end

    def __param_length(var_name)
      # ${#var} - length of variable value
      value = __get_special_var(var_name) || Builtins.get_var(var_name) || ''
      value.length.to_s
    end

    def __param_substring(var_name, offset, length)
      # ${var:offset} or ${var:offset:length}
      value = __get_special_var(var_name) || Builtins.get_var(var_name) || ''
      offset = offset.to_i
      if length
        length = length.to_i
        if length < 0
          # Negative length means from end
          value[offset...length]
        else
          value[offset, length]
        end
      else
        value[offset..]
      end || ''
    end

    def __param_transform(var_name, operator)
      # ${var@operator} - transformation operators
      value = __get_special_var(var_name) || Builtins.get_var(var_name)

      case operator
      when 'Q'
        # Quote the value for reuse as input
        return "''" if value.nil?
        "'" + value.gsub("'") { "'\\''" } + "'"
      when 'E'
        # Expand escape sequences like $'...'
        return '' if value.nil?
        Builtins.process_escape_sequences(value)
      when 'P'
        # Expand as prompt string (PS1-style)
        return '' if value.nil?
        expand_prompt(value)
      when 'A'
        # Assignment statement form
        if value.nil?
          "declare -- #{var_name}"
        elsif Builtins.exported?(var_name)
          "declare -x #{var_name}=#{__param_transform(var_name, 'Q')}"
        else
          "declare -- #{var_name}=#{__param_transform(var_name, 'Q')}"
        end
      when 'a'
        # Attribute flags
        flags = +''
        flags << 'x' if Builtins.exported?(var_name)
        flags << 'r' if Builtins.readonly?(var_name)
        flags
      when 'U'
        # Uppercase entire value
        return '' if value.nil?
        value.upcase
      when 'u'
        # Uppercase first character
        return '' if value.nil?
        return '' if value.empty?
        value[0].upcase + (value[1..] || '')
      when 'L'
        # Lowercase entire value
        return '' if value.nil?
        value.downcase
      when 'K'
        # For associative arrays, show key-value pairs
        # For regular variables, just show quoted value
        return "''" if value.nil?
        __param_transform(var_name, 'Q')
      else
        value || ''
      end
    end

    def __get_special_var(var_name)
      # Returns value for special variables, or nil if not a special variable
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
      when 'RUBISH_MONOSECONDS', 'BASH_MONOSECONDS' then __bash_monoseconds.to_s
      when 'RUBISH_VERSION', 'BASH_VERSION' then Rubish::VERSION
      when 'OSTYPE' then __ostype
      when 'HOSTTYPE' then __hosttype
      when 'MACHTYPE' then RUBY_PLATFORM
      when 'RUBISH_COMMAND', 'BASH_COMMAND' then @rubish_command
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
      when 'BASH_ARGV0' then @bash_argv0_unset ? nil : __bash_argv0
      when 'RUBISH_EXECUTION_STRING', 'BASH_EXECUTION_STRING' then ENV['RUBISH_EXECUTION_STRING'] || ''
      when 'RUBISH', 'BASH' then __rubish_path
      when 'RUBISH_TRAPSIG', 'BASH_TRAPSIG' then Builtins.current_trapsig || ''
      when 'READLINE_LINE' then Builtins.readline_line
      when 'READLINE_POINT' then Builtins.readline_point.to_s
      when 'READLINE_MARK' then Builtins.readline_mark.to_s
      end
    end

    def __param_replace(var_name, operator, pattern, replacement)
      # ${var/pattern/replacement} or ${var//pattern/replacement}
      value = __get_special_var(var_name) || Builtins.get_var(var_name) || ''
      return '' if value.empty?

      # Convert shell pattern to regex
      regex = pattern_to_regex(pattern, :any, :longest)

      # Process replacement string for & substitution when patsub_replacement is enabled
      replacement_proc = if Builtins.shopt_enabled?('patsub_replacement') && replacement.include?('&')
                           proc do |match|
                             # Replace unescaped & with the matched text
                             # \& is a literal &
                             result = +''
                             i = 0
                             while i < replacement.length
                               if replacement[i] == '\\' && i + 1 < replacement.length && replacement[i + 1] == '&'
                                 # Escaped &, output literal &
                                 result << '&'
                                 i += 2
                               elsif replacement[i] == '&'
                                 # Unescaped &, replace with match
                                 result << match
                                 i += 1
                               else
                                 result << replacement[i]
                                 i += 1
                               end
                             end
                             result
                           end
                         else
                           nil
                         end

      case operator
      when '//'
        # Replace all occurrences
        if replacement_proc
          value.gsub(regex, &replacement_proc)
        else
          value.gsub(regex, replacement)
        end
      when '/'
        # Replace first occurrence only
        if replacement_proc
          value.sub(regex, &replacement_proc)
        else
          value.sub(regex, replacement)
        end
      else
        value
      end
    end

    def __param_case(var_name, operator, pattern)
      # Case modification operators
      value = Builtins.get_var(var_name) || ''
      return '' if value.empty?

      case operator
      when '^^'
        # Uppercase all characters
        if pattern.empty?
          value.upcase
        else
          # Only uppercase characters matching pattern
          regex = pattern_to_regex(pattern, :any, :longest)
          value.gsub(regex) { |m| m.upcase }
        end
      when '^'
        # Uppercase first character
        if pattern.empty?
          value[0].upcase + value[1..]
        else
          # Uppercase first char if it matches pattern
          regex = pattern_to_regex(pattern, :any, :longest)
          if value[0].match?(regex)
            value[0].upcase + value[1..]
          else
            value
          end
        end
      when ',,'
        # Lowercase all characters
        if pattern.empty?
          value.downcase
        else
          # Only lowercase characters matching pattern
          regex = pattern_to_regex(pattern, :any, :longest)
          value.gsub(regex) { |m| m.downcase }
        end
      when ','
        # Lowercase first character
        if pattern.empty?
          value[0].downcase + value[1..]
        else
          # Lowercase first char if it matches pattern
          regex = pattern_to_regex(pattern, :any, :longest)
          if value[0].match?(regex)
            value[0].downcase + value[1..]
          else
            value
          end
        end
      else
        value
      end
    end

    def __param_indirect(var_name)
      # ${!var} - get value of variable whose name is in var
      indirect_name = Builtins.get_var(var_name)
      return '' if indirect_name.nil? || indirect_name.empty?
      Builtins.get_var(indirect_name) || ''
    end

    def __rubish_versinfo
      # Returns RUBISH_VERSINFO array similar to BASH_VERSINFO
      # [0] major, [1] minor, [2] patch, [3] extra, [4] release status, [5] machine type
      parts = Rubish::VERSION.split('.')
      [
        parts[0] || '0',           # major
        parts[1] || '0',           # minor
        parts[2] || '0',           # patch
        '',                        # extra version info
        'release',                 # release status
        RUBY_PLATFORM              # machine type
      ]
    end

    def __ostype
      # Returns OS type from RUBY_PLATFORM (e.g., "darwin23", "linux-gnu")
      # RUBY_PLATFORM format: "arch-os" like "arm64-darwin23" or "x86_64-linux-gnu"
      parts = RUBY_PLATFORM.split('-', 2)
      parts[1] || RUBY_PLATFORM
    end

    def __hosttype
      # Returns host/machine type from RUBY_PLATFORM (e.g., "arm64", "x86_64")
      RUBY_PLATFORM.split('-').first
    end

    def __bash_monoseconds
      # Returns the value from the system's monotonic clock in seconds
      # The monotonic clock is not affected by system time changes
      # Falls back to EPOCHSECONDS equivalent if monotonic clock unavailable
      if defined?(Process::CLOCK_MONOTONIC)
        Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i
      else
        Time.now.to_i
      end
    end

    def __bash_argv0
      # Returns the same value as $0 (the shell or script name)
      # BASH_ARGV0 expands to the name of the shell or shell script
      # RUBISH_ARGV0 overrides @script_name if set (even if empty)
      Builtins.var_set?('RUBISH_ARGV0') ? Builtins.get_var('RUBISH_ARGV0') : @script_name
    end

    def __rubish_path
      # Returns the full pathname used to invoke rubish (like BASH in bash)
      # Try to find the rubish executable path
      @rubish_path ||= begin
        # First check if we're running as a script
        if $PROGRAM_NAME && File.exist?($PROGRAM_NAME)
          File.expand_path($PROGRAM_NAME)
        else
          # Try to find rubish in common locations
          bin_path = File.expand_path('../../bin/rubish', __dir__)
          if File.exist?(bin_path)
            bin_path
          else
            # Fall back to searching PATH
            path_dirs = (ENV['PATH'] || '').split(':')
            rubish_in_path = path_dirs.map { |d| File.join(d, 'rubish') }.find { |p| File.exist?(p) }
            rubish_in_path || $PROGRAM_NAME || 'rubish'
          end
        end
      end
    end

    def __translate(string)
      # $"string" - locale-specific translation using TEXTDOMAIN
      # Uses gettext if available, otherwise returns original string

      # noexpand_translation: do not expand $"..." strings for translation
      return string if Builtins.shopt_enabled?('noexpand_translation')

      textdomain = ENV['TEXTDOMAIN']
      return string if textdomain.nil? || textdomain.empty?

      # Try to use gettext for translation
      begin
        require 'gettext'
        textdomaindir = ENV['TEXTDOMAINDIR']
        if textdomaindir && !textdomaindir.empty?
          GetText.bindtextdomain(textdomain, path: textdomaindir)
        else
          GetText.bindtextdomain(textdomain)
        end
        GetText._(string)
      rescue LoadError
        # gettext gem not available, return original string
        string
      rescue StandardError
        # Any other error, return original string
        string
      end
    end

    def __array_element(var_name, index)
      # ${arr[n]} or ${map[key]} - get array/assoc element
      # For associative arrays, expand as string (key lookup)
      # For indexed arrays, evaluate as arithmetic expression (expands bare variable names)
      if Builtins.assoc_array?(var_name) || SPECIAL_ASSOC_ARRAYS.include?(var_name)
        expanded_index = expand_string_content(index)
        # assoc_expand_once: when disabled, subscripts may be expanded again
        unless Builtins.shopt_enabled?('assoc_expand_once')
          if expanded_index.include?('$')
            expanded_index = expand_string_content(expanded_index)
          end
        end
      else
        # Indexed array: evaluate subscript as arithmetic expression
        # This allows bare variable names like ${arr[COMP_CWORD]} to expand
        begin
          expanded_index = eval_arithmetic_expr(index).to_s
        rescue
          expanded_index = expand_string_content(index)
        end

        # array_expand_once (bash 5.2+): when disabled, subscripts may be expanded again
        unless Builtins.shopt_enabled?('array_expand_once')
          if expanded_index.include?('$')
            expanded_index = expand_string_content(expanded_index)
          end
        end
      end

      # Special handling for GROUPS array
      if var_name == 'GROUPS'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        groups = Process.groups
        return (groups[idx] || '').to_s
      end

      # Special handling for RUBISH_VERSINFO and BASH_VERSINFO arrays
      if var_name == 'RUBISH_VERSINFO' || var_name == 'BASH_VERSINFO'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        return (__rubish_versinfo[idx] || '').to_s
      end

      # Special handling for PIPESTATUS array
      if var_name == 'PIPESTATUS'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        return (@pipestatus[idx] || '').to_s
      end

      # Special handling for FUNCNAME array
      if var_name == 'FUNCNAME'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        return (@funcname_stack[idx] || '').to_s
      end

      # Special handling for RUBISH_LINENO and BASH_LINENO arrays
      if var_name == 'RUBISH_LINENO' || var_name == 'BASH_LINENO'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        return (@rubish_lineno_stack[idx] || '').to_s
      end

      # Special handling for RUBISH_SOURCE and BASH_SOURCE arrays
      if var_name == 'RUBISH_SOURCE' || var_name == 'BASH_SOURCE'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        return (@rubish_source_stack[idx] || '').to_s
      end

      # Special handling for RUBISH_ARGC and BASH_ARGC arrays
      if var_name == 'RUBISH_ARGC' || var_name == 'BASH_ARGC'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        return (@rubish_argc_stack[idx] || '').to_s
      end

      # Special handling for RUBISH_ARGV and BASH_ARGV arrays
      if var_name == 'RUBISH_ARGV' || var_name == 'BASH_ARGV'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        return (@rubish_argv_stack[idx] || '').to_s
      end

      # Special handling for DIRSTACK array
      if var_name == 'DIRSTACK'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        dirstack = [Dir.pwd] + Builtins.dir_stack
        return (dirstack[idx] || '').to_s
      end

      # Special handling for RUBISH_ALIASES associative array
      if var_name == 'RUBISH_ALIASES'
        return (Builtins.aliases[expanded_index] || '').to_s
      end

      # Special handling for RUBISH_CMDS associative array (command hash)
      if var_name == 'RUBISH_CMDS'
        return (Builtins.command_hash[expanded_index] || '').to_s
      end

      # Special handling for COMP_WORDS array
      if var_name == 'COMP_WORDS'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        return (Builtins.comp_words[idx] || '').to_s
      end

      # Special handling for COMPREPLY array
      if var_name == 'COMPREPLY'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        return (Builtins.compreply[idx] || '').to_s
      end

      # Special handling for RUBISH_REMATCH and BASH_REMATCH arrays
      if var_name == 'RUBISH_REMATCH' || var_name == 'BASH_REMATCH'
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        return Builtins.get_array_element('RUBISH_REMATCH', idx)
      end

      if Builtins.assoc_array?(var_name)
        # Associative array - use key directly
        Builtins.get_assoc_element(var_name, expanded_index)
      else
        # Indexed array - evaluate as integer
        idx = begin
          eval(expanded_index).to_i
        rescue
          expanded_index.to_i
        end
        Builtins.get_array_element(var_name, idx)
      end
    end

    def __array_all(var_name, mode)
      # ${arr[@]} or ${arr[*]} - get all array/assoc values
      # Special handling for GROUPS array
      if var_name == 'GROUPS'
        values = Process.groups.map(&:to_s)
      # Special handling for RUBISH_VERSINFO and BASH_VERSINFO arrays
      elsif var_name == 'RUBISH_VERSINFO' || var_name == 'BASH_VERSINFO'
        values = __rubish_versinfo
      # Special handling for PIPESTATUS array
      elsif var_name == 'PIPESTATUS'
        values = @pipestatus.map(&:to_s)
      # Special handling for FUNCNAME array
      elsif var_name == 'FUNCNAME'
        values = @funcname_stack.dup
      # Special handling for RUBISH_LINENO and BASH_LINENO arrays
      elsif var_name == 'RUBISH_LINENO' || var_name == 'BASH_LINENO'
        values = @rubish_lineno_stack.map(&:to_s)
      # Special handling for RUBISH_SOURCE and BASH_SOURCE arrays
      elsif var_name == 'RUBISH_SOURCE' || var_name == 'BASH_SOURCE'
        values = @rubish_source_stack.dup
      # Special handling for RUBISH_ARGC and BASH_ARGC arrays
      elsif var_name == 'RUBISH_ARGC' || var_name == 'BASH_ARGC'
        values = @rubish_argc_stack.map(&:to_s)
      # Special handling for RUBISH_ARGV and BASH_ARGV arrays
      elsif var_name == 'RUBISH_ARGV' || var_name == 'BASH_ARGV'
        values = @rubish_argv_stack.dup
      # Special handling for DIRSTACK array
      elsif var_name == 'DIRSTACK'
        values = [Dir.pwd] + Builtins.dir_stack
      # Special handling for RUBISH_ALIASES and BASH_ALIASES associative arrays
      elsif var_name == 'RUBISH_ALIASES' || var_name == 'BASH_ALIASES'
        values = Builtins.aliases.values
      # Special handling for RUBISH_CMDS and BASH_CMDS associative arrays (command hash)
      elsif var_name == 'RUBISH_CMDS' || var_name == 'BASH_CMDS'
        values = Builtins.command_hash.values
      # Special handling for COMP_WORDS array
      elsif var_name == 'COMP_WORDS'
        values = Builtins.comp_words.dup
      # Special handling for COMPREPLY array
      elsif var_name == 'COMPREPLY'
        values = Builtins.compreply.dup
      # Special handling for RUBISH_REMATCH and BASH_REMATCH arrays
      elsif var_name == 'RUBISH_REMATCH' || var_name == 'BASH_REMATCH'
        values = Builtins.get_array('RUBISH_REMATCH').compact
      elsif Builtins.assoc_array?(var_name)
        values = Builtins.assoc_values(var_name)
      else
        values = Builtins.get_array(var_name).compact
      end

      if mode == '@'
        values.join(' ')
      else
        # $* joins with first character of IFS
        Builtins.join_by_ifs(values)
      end
    end

    def __array_length(var_name)
      # ${#arr[@]} - get array/assoc length
      # Special handling for GROUPS array
      if var_name == 'GROUPS'
        Process.groups.length.to_s
      # Special handling for RUBISH_VERSINFO and BASH_VERSINFO arrays
      elsif var_name == 'RUBISH_VERSINFO' || var_name == 'BASH_VERSINFO'
        __rubish_versinfo.length.to_s
      # Special handling for PIPESTATUS array
      elsif var_name == 'PIPESTATUS'
        @pipestatus.length.to_s
      # Special handling for FUNCNAME array
      elsif var_name == 'FUNCNAME'
        @funcname_stack.length.to_s
      # Special handling for RUBISH_LINENO and BASH_LINENO arrays
      elsif var_name == 'RUBISH_LINENO' || var_name == 'BASH_LINENO'
        @rubish_lineno_stack.length.to_s
      # Special handling for RUBISH_SOURCE and BASH_SOURCE arrays
      elsif var_name == 'RUBISH_SOURCE' || var_name == 'BASH_SOURCE'
        @rubish_source_stack.length.to_s
      # Special handling for RUBISH_ARGC and BASH_ARGC arrays
      elsif var_name == 'RUBISH_ARGC' || var_name == 'BASH_ARGC'
        @rubish_argc_stack.length.to_s
      # Special handling for RUBISH_ARGV and BASH_ARGV arrays
      elsif var_name == 'RUBISH_ARGV' || var_name == 'BASH_ARGV'
        @rubish_argv_stack.length.to_s
      # Special handling for DIRSTACK array
      elsif var_name == 'DIRSTACK'
        ([Dir.pwd] + Builtins.dir_stack).length.to_s
      # Special handling for RUBISH_ALIASES and BASH_ALIASES associative arrays
      elsif var_name == 'RUBISH_ALIASES' || var_name == 'BASH_ALIASES'
        Builtins.aliases.length.to_s
      # Special handling for RUBISH_CMDS and BASH_CMDS associative arrays (command hash)
      elsif var_name == 'RUBISH_CMDS' || var_name == 'BASH_CMDS'
        Builtins.command_hash.length.to_s
      # Special handling for COMP_WORDS array
      elsif var_name == 'COMP_WORDS'
        Builtins.comp_words.length.to_s
      # Special handling for COMPREPLY array
      elsif var_name == 'COMPREPLY'
        Builtins.compreply.length.to_s
      # Special handling for RUBISH_REMATCH and BASH_REMATCH arrays
      elsif var_name == 'RUBISH_REMATCH' || var_name == 'BASH_REMATCH'
        Builtins.array_length('RUBISH_REMATCH').to_s
      elsif Builtins.assoc_array?(var_name)
        Builtins.assoc_length(var_name).to_s
      else
        Builtins.array_length(var_name).to_s
      end
    end

    def __array_keys(var_name)
      # ${!arr[@]} - get array indices or assoc keys
      # Special handling for GROUPS array
      if var_name == 'GROUPS'
        (0...Process.groups.length).to_a.join(' ')
      # Special handling for RUBISH_VERSINFO and BASH_VERSINFO arrays
      elsif var_name == 'RUBISH_VERSINFO' || var_name == 'BASH_VERSINFO'
        (0...__rubish_versinfo.length).to_a.join(' ')
      # Special handling for PIPESTATUS array
      elsif var_name == 'PIPESTATUS'
        (0...@pipestatus.length).to_a.join(' ')
      # Special handling for FUNCNAME array
      elsif var_name == 'FUNCNAME'
        (0...@funcname_stack.length).to_a.join(' ')
      # Special handling for RUBISH_LINENO and BASH_LINENO arrays
      elsif var_name == 'RUBISH_LINENO' || var_name == 'BASH_LINENO'
        (0...@rubish_lineno_stack.length).to_a.join(' ')
      # Special handling for RUBISH_SOURCE and BASH_SOURCE arrays
      elsif var_name == 'RUBISH_SOURCE' || var_name == 'BASH_SOURCE'
        (0...@rubish_source_stack.length).to_a.join(' ')
      # Special handling for RUBISH_ARGC and BASH_ARGC arrays
      elsif var_name == 'RUBISH_ARGC' || var_name == 'BASH_ARGC'
        (0...@rubish_argc_stack.length).to_a.join(' ')
      # Special handling for RUBISH_ARGV and BASH_ARGV arrays
      elsif var_name == 'RUBISH_ARGV' || var_name == 'BASH_ARGV'
        (0...@rubish_argv_stack.length).to_a.join(' ')
      # Special handling for DIRSTACK array
      elsif var_name == 'DIRSTACK'
        (0...([Dir.pwd] + Builtins.dir_stack).length).to_a.join(' ')
      # Special handling for RUBISH_ALIASES and BASH_ALIASES associative arrays
      elsif var_name == 'RUBISH_ALIASES' || var_name == 'BASH_ALIASES'
        Builtins.aliases.keys.join(' ')
      # Special handling for RUBISH_CMDS and BASH_CMDS associative arrays (command hash)
      elsif var_name == 'RUBISH_CMDS' || var_name == 'BASH_CMDS'
        Builtins.command_hash.keys.join(' ')
      # Special handling for COMP_WORDS array
      elsif var_name == 'COMP_WORDS'
        (0...Builtins.comp_words.length).to_a.join(' ')
      # Special handling for COMPREPLY array
      elsif var_name == 'COMPREPLY'
        (0...Builtins.compreply.length).to_a.join(' ')
      # Special handling for RUBISH_REMATCH and BASH_REMATCH arrays
      elsif var_name == 'RUBISH_REMATCH' || var_name == 'BASH_REMATCH'
        arr = Builtins.get_array('RUBISH_REMATCH')
        arr.each_index.select { |i| !arr[i].nil? }.join(' ')
      elsif Builtins.assoc_array?(var_name)
        Builtins.assoc_keys(var_name).join(' ')
      else
        arr = Builtins.get_array(var_name)
        arr.each_index.select { |i| !arr[i].nil? }.join(' ')
      end
    end

    def remove_suffix(value, pattern, mode)
      # For suffix removal, we need to find where the pattern matches at the end
      # For shortest (%), we want the rightmost match start position
      # For longest (%%), we want the leftmost match start position
      # The regex must match the ENTIRE suffix (anchored at both ends)
      regex = pattern_to_regex(pattern, :full, mode)

      if mode == :shortest
        # Try matching from the end, progressively looking for shorter matches
        (value.length - 1).downto(0) do |i|
          if regex.match?(value[i..])
            return value[0...i]
          end
        end
        value  # No match
      else
        # For longest, find the earliest position where pattern matches to end
        (0...value.length).each do |i|
          if regex.match?(value[i..])
            return value[0...i]
          end
        end
        value  # No match
      end
    end

    def pattern_to_regex(pattern, position, greedy)
      # Convert shell glob pattern to regex
      # * -> .* or .*?
      # ? -> .
      # [...] -> [...]
      regex_str = +''
      i = 0
      while i < pattern.length
        char = pattern[i]
        case char
        when '*'
          regex_str << (greedy == :longest ? '.*' : '.*?')
        when '?'
          regex_str << '.'
        when '['
          # Find matching ]
          j = i + 1
          j += 1 if j < pattern.length && pattern[j] == '!'
          j += 1 if j < pattern.length && pattern[j] == ']'
          j += 1 while j < pattern.length && pattern[j] != ']'
          if j < pattern.length
            bracket = pattern[i..j]
            bracket = bracket.sub('[!', '[^')  # Convert [! to [^
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
      when :prefix
        Regexp.new("\\A#{regex_str}")
      when :suffix
        Regexp.new("#{regex_str}\\z")
      when :full
        Regexp.new("\\A#{regex_str}\\z")
      else
        Regexp.new(regex_str)
      end
    end
  end
end
