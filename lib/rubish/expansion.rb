# frozen_string_literal: true

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
      OSTYPE HOSTTYPE MACHTYPE PIPESTATUS RUBISH_COMMAND BASH_COMMAND
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

    def handle_bare_assignments(assignments)
      assignments.each do |assignment|
        if assignment =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\+?=\((.*)\)\z/m
          handle_array_assignment($1, $2, assignment.include?('+='))
        elsif assignment =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\]=(.*)\z/
          handle_array_element_assignment($1, $2, $3)
        elsif assignment =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)=(.*)\z/m
          handle_scalar_assignment($1, $2)
        end
      end
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
      return [arg] unless arg.is_a?(String)

      # Handle quoted strings
      result = expand_quoted_string(arg) { nil }
      return [result] if result

      # Brace expansion first (only if braceexpand option is enabled)
      brace_expanded = if Builtins.set_option?('B') && arg.include?('{') && !arg.start_with?('$')
                         expand_braces(arg)
                       else
                         [arg]
                       end

      # Then expand variables and globs on each result
      brace_expanded.flat_map do |item|
        expanded = expand_string_content(item)
        next [] if expanded.empty?
        expanded.match?(/[*?\[]/) ? __glob(expanded) : [expanded]
      end
    end

    def expand_single_arg_with_glob(arg)
      return [arg] unless arg.is_a?(String)

      result = expand_quoted_string(arg) { nil }
      return [result] if result

      expanded = expand_string_content(arg)
      return [] if expanded.empty?
      expanded.match?(/[*?\[]/) ? __glob(expanded) : [expanded]
    end

    def expand_single_arg(arg)
      return arg unless arg.is_a?(String)

      result = expand_quoted_string(arg) { nil }
      return result if result

      expand_string_content(arg)
    end

    # Expand variables and command substitution in a string
    # In double quotes, only \$, \`, \", \\, and \newline are special escape sequences
    def expand_string_content(str)
      result = +''
      i = 0

      while i < str.length
        char = str[i]

        if char == '\\'
          # Escape sequence - only consume backslash for special characters
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
                result << __translate(expand_string_content(content))
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
          return [__run_subst(str[pos + 1...j]), j - pos + 1]
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
      # ${#arr[@]} or ${#arr[*]} - array length
      return __array_length($1) if content =~ /\A#([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\z/

      # ${!arr[@]} or ${!arr[*]} - array keys/indices
      return __array_keys($1) if content =~ /\A!([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\z/

      # ${arr[@]} or ${arr[*]} - all array elements
      return __array_all($1, $2) if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([@*])\]\z/

      # ${arr[n]} - array element access
      return __array_element($1, $2) if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\]\z/

      # ${var:-default}, ${var-default}, etc.
      return __param_expand($1, $2, $3 || '') if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)(:-|:=|:\+|:\?|-|=|\+|\?)(.*)?\z/

      # ${#var} - length
      return __param_length($1) if content =~ /\A#([a-zA-Z_][a-zA-Z0-9_]*)\z/

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
          break if prev_char.nil? || prev_char =~ /\s/
          result << char
          i += 1
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
        elsif char == '~' && !in_single_quotes
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
          bin_path = File.expand_path('../../bin/rubish', __dir__)
          if File.exist?(bin_path)
            bin_path
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
    def pattern_to_regex(pattern, position, greedy)
      regex_str = +''
      i = 0
      while i < pattern.length
        char = pattern[i]
        case char
        when '*' then regex_str << (greedy == :longest ? '.*' : '.*?')
        when '?' then regex_str << '.'
        when '['
          j = i + 1
          j += 1 if j < pattern.length && pattern[j] == '!'
          j += 1 if j < pattern.length && pattern[j] == ']'
          j += 1 while j < pattern.length && pattern[j] != ']'
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
    def expand_quoted_string(value)
      if value.start_with?("$'") && value.end_with?("'")
        Builtins.process_escape_sequences(value[2...-1])
      elsif value.start_with?("'") && value.end_with?("'")
        value[1...-1]
      elsif value.start_with?('"') && value.end_with?('"')
        expand_string_content(value[1...-1])
      else
        yield  # Return nil or call the block for unquoted handling
      end
    end

    # Handle array assignment: arr=(a b c) or arr+=(d e) or map=([k]=v ...)
    def handle_array_assignment(var_name, elements_str, is_append)
      if elements_str =~ /\A\s*\[/ || Builtins.assoc_array?(var_name)
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
        elsif is_append
          Builtins.array_append(var_name, elements)
        else
          Builtins.set_array(var_name, elements)
        end
      end
    end

    # Handle array element assignment: arr[0]=value or map[key]=value
    def handle_array_element_assignment(var_name, key, value)
      expanded_key = expand_string_content(key)
      expanded_value = expand_assignment_value(value)

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
        Builtins.set_var(var_name, expanded_value)
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
        return [ENV['PWD'] || Dir.pwd, 2] if line[i + 2].nil? || line[i + 2] =~ %r{[\s/]}
      when '-'
        if line[i + 2].nil? || line[i + 2] =~ %r{[\s/]}
          return ENV['OLDPWD'] ? [ENV['OLDPWD'], 2] : ['~-', 2]
        end
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
      when 'RUBISH_EXECUTION_STRING', 'BASH_EXECUTION_STRING' then ENV['RUBISH_EXECUTION_STRING'] || ''
      when 'RUBISH', 'BASH' then rubish_path
      when 'RUBISH_TRAPSIG', 'BASH_TRAPSIG' then Builtins.current_trapsig || ''
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
      eval(expanded_index).to_i
    rescue
      expanded_index.to_i
    end

    # Get values for special shell arrays (GROUPS, PIPESTATUS, FUNCNAME, etc.)
    # Returns Array for indexed arrays, :assoc for special associative arrays, nil otherwise
    def get_special_array_values(var_name)
      case var_name
      when 'GROUPS' then Process.groups
      when 'RUBISH_VERSINFO', 'BASH_VERSINFO' then rubish_versinfo
      when 'PIPESTATUS' then @pipestatus
      when 'FUNCNAME' then @funcname_stack
      when 'RUBISH_LINENO', 'BASH_LINENO' then @rubish_lineno_stack
      when 'RUBISH_SOURCE', 'BASH_SOURCE' then @rubish_source_stack
      when 'RUBISH_ARGC', 'BASH_ARGC' then @rubish_argc_stack
      when 'RUBISH_ARGV', 'BASH_ARGV' then @rubish_argv_stack
      when 'DIRSTACK' then [Dir.pwd] + Builtins.dir_stack
      when 'COMP_WORDS' then Builtins.comp_words
      when 'COMPREPLY' then Builtins.compreply
      when 'RUBISH_REMATCH', 'BASH_REMATCH' then Builtins.get_array('RUBISH_REMATCH')
      when 'RUBISH_ALIASES', 'BASH_ALIASES', 'RUBISH_CMDS', 'BASH_CMDS' then :assoc
      end
    end

    def get_special_assoc_value(var_name, key)
      case var_name
      when 'RUBISH_ALIASES', 'BASH_ALIASES' then (Builtins.aliases[key] || '').to_s
      when 'RUBISH_CMDS', 'BASH_CMDS' then (Builtins.command_hash[key] || '').to_s
      else ''
      end
    end

    def get_special_assoc_all_values(var_name)
      case var_name
      when 'RUBISH_ALIASES', 'BASH_ALIASES' then Builtins.aliases.values
      when 'RUBISH_CMDS', 'BASH_CMDS' then Builtins.command_hash.values
      else []
      end
    end

    def get_special_assoc_length(var_name)
      case var_name
      when 'RUBISH_ALIASES', 'BASH_ALIASES' then Builtins.aliases.length
      when 'RUBISH_CMDS', 'BASH_CMDS' then Builtins.command_hash.length
      else 0
      end
    end

    def get_special_assoc_keys(var_name)
      case var_name
      when 'RUBISH_ALIASES', 'BASH_ALIASES' then Builtins.aliases.keys
      when 'RUBISH_CMDS', 'BASH_CMDS' then Builtins.command_hash.keys
      else []
      end
    end
  end
end
