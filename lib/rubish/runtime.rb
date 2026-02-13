# frozen_string_literal: true

module Rubish
  # Runtime methods called from generated Ruby code (codegen output)
  # Methods in this module have __ prefix and are the interface between
  # codegen and the shell execution
  module Runtime
    # === Arithmetic methods ===

    def __arith_for_loop(init_expr, cond_expr, update_expr, &block)
      # C-style arithmetic for loop: for ((init; cond; update)); do body; done
      # Evaluate init expression once
      eval_arithmetic_expr(init_expr) unless init_expr.empty?

      # Loop while condition is true (non-zero)
      loop do
        # If condition is empty, it's always true (infinite loop)
        unless cond_expr.empty?
          result = eval_arithmetic_expr(cond_expr)
          break if result == 0  # Condition is false
        end

        # Execute body
        block.call

        # Evaluate update expression
        eval_arithmetic_expr(update_expr) unless update_expr.empty?
      end
    end

    def __arith(expr)
      # Evaluate arithmetic expression
      # Replace variable references with their values
      # Also handle positional parameters like $1, $2, etc.
      expanded = expr.gsub(/\$\{([^}]+)\}|\$(\d+)|\$([a-zA-Z_][a-zA-Z0-9_]*)|([a-zA-Z_][a-zA-Z0-9_]*)/) do |match|
        if $2 # Positional parameter like $1, $2
          n = $2.to_i
          (@positional_params[n - 1] || '0')
        elsif (var_name = $1 || $3 || $4)
          # Use get_special_var for special variables, fall back to ENV
          get_special_var(var_name) || ENV.fetch(var_name, '0')
        else
          match
        end
      end

      # Evaluate the expression safely (only allow arithmetic)
      # Convert shell operators to Ruby: ** for exponentiation is same
      # Note: bash uses ** for exponent, which Ruby also supports
      begin
        result = Kernel.eval(expanded)
        result.to_s
      rescue StandardError
        '0'
      end
    end

    def __arithmetic_command(expr)
      # Evaluate (( )) arithmetic command
      # Returns exit status 0 if result is non-zero, 1 if result is zero
      # Supports variable assignments like x=1, x++, x--, ++x, --x, x+=1, etc.
      result = eval_arithmetic_expr(expr)
      ExitStatus.new(result != 0 ? 0 : 1)
    end

    # === Expansion methods ===

    # Run command substitution within rubish itself (not external shell)
    # This allows user-defined functions to be available in $() substitution
    # Forks a subprocess, captures stdout, and returns the output (with trailing newlines removed)
    def __run_subst(cmd)
      reader, writer = IO.pipe
      # inherit_errexit: if disabled, child should not inherit errexit (set -e)
      inherit_errexit = Builtins.shopt_enabled?('inherit_errexit')

      pid = fork do
        reader.close
        # Redirect stdout to the pipe using the constant STDOUT
        # This works even if $stdout has been redirected to a StringIO (for testing)
        STDOUT.reopen(writer)
        $stdout = STDOUT

        # Suppress stderr during completion to avoid spurious output on terminal
        if Builtins.in_completion_context?
          STDERR.reopen(File.open(File::NULL, 'w'))
          $stderr = STDERR
        end

        # Command substitution only inherits errexit when inherit_errexit is enabled
        Builtins.current_state.set_options['e'] = false unless inherit_errexit

        begin
          exit_code = catch(:exit) do
            execute(cmd, skip_history_expansion: true)
            @last_status
          end
          Kernel.exit(exit_code || 0)
        rescue => e
          $stderr.puts "rubish: #{e.message}" unless Builtins.in_completion_context?
          Kernel.exit(1)
        end
      end

      writer.close
      output = reader.read.chomp
      reader.close

      Process.wait(pid)
      @last_status = $?.exitstatus || 0
      output
    end

    # Parameter expansion operations
    # Operators:
    #   :-  Use default if unset or null
    #   -   Use default only if unset (null is fine)
    #   :=  Assign default if unset or null
    #   =   Assign default only if unset
    #   :+  Use value if set and non-null
    #   +   Use value if set (even if null)
    #   :?  Error if unset or null
    #   ?   Error only if unset
    #   #   Remove shortest prefix matching pattern
    #   ##  Remove longest prefix matching pattern
    #   %   Remove shortest suffix matching pattern
    #   %%  Remove longest suffix matching pattern
    def __param_expand(var_name, operator, operand)
      # extquote: when enabled, process $'...' and $"..." quoting in the operand
      operand = expand_extquote(operand) if Builtins.shopt_enabled?('extquote')

      value, is_set, is_null = get_param_expand_info(var_name)

      case operator
      when ':-' then is_null ? operand : value                    # ${var:-default}
      when '-' then is_set ? value : operand                      # ${var-default}
      when ':=' then is_null ? assign_default(var_name, operand) : value  # ${var:=default}
      when '=' then is_set ? value : assign_default(var_name, operand)    # ${var=default}
      when ':+' then is_null ? '' : operand                       # ${var:+value}
      when '+' then is_set ? operand : ''                         # ${var+value}
      when ':?'                                                   # ${var:?message}
        raise(operand.empty? ? "#{var_name}: parameter null or not set" : operand) if is_null
        value
      when '?'                                                    # ${var?message}
        raise(operand.empty? ? "#{var_name}: parameter not set" : operand) unless is_set
        value || ''
      when '#'                                                    # ${var#pattern}
        return '' if value.nil?
        pattern_to_regex(operand, :prefix, :shortest).match(value) { |m| value[m.end(0)..] } || value
      when '##'                                                   # ${var##pattern}
        return '' if value.nil?
        pattern_to_regex(operand, :prefix, :longest).match(value) { |m| value[m.end(0)..] } || value
      when '%' then value.nil? ? '' : remove_suffix(value, operand, :shortest)   # ${var%pattern}
      when '%%' then value.nil? ? '' : remove_suffix(value, operand, :longest)   # ${var%%pattern}
      else value || ''
      end
    end

    # ${#var} - length of variable value
    def __param_length(var_name)
      (get_special_var(var_name) || Builtins.get_var(var_name) || '').length.to_s
    end

    # ${var:offset} or ${var:offset:length} - substring extraction
    def __param_substring(var_name, offset, length)
      value = get_special_var(var_name) || Builtins.get_var(var_name) || ''
      offset = offset.to_i
      if length
        length = length.to_i
        # Negative length means from end
        length < 0 ? value[offset...length] : value[offset, length]
      else
        value[offset..]
      end || ''
    end

    # ${var@operator} - transformation operators
    # Q: Quote for reuse as input
    # E: Expand escape sequences like $'...'
    # P: Expand as prompt string (PS1-style)
    # A: Assignment statement form
    # a: Attribute flags
    # U: Uppercase entire value
    # u: Uppercase first character
    # L: Lowercase entire value
    # K: For associative arrays, show key-value pairs
    def __param_transform(var_name, operator)
      value = get_special_var(var_name) || Builtins.get_var(var_name)

      case operator
      when 'Q' then value.nil? ? "''" : "'" + value.gsub("'") { "'\\''" } + "'"
      when 'E' then value.nil? ? '' : Builtins.process_escape_sequences(value)
      when 'P' then value.nil? ? '' : expand_prompt(value)
      when 'A'
        if value.nil?
          "declare -- #{var_name}"
        else
          prefix = Builtins.exported?(var_name) ? 'declare -x' : 'declare --'
          "#{prefix} #{var_name}=#{__param_transform(var_name, 'Q')}"
        end
      when 'a'
        flags = +''
        flags << 'x' if Builtins.exported?(var_name)
        flags << 'r' if Builtins.readonly?(var_name)
        flags
      when 'U' then value&.upcase || ''
      when 'u' then value.nil? || value.empty? ? '' : value[0].upcase + (value[1..] || '')
      when 'L' then value&.downcase || ''
      when 'K' then value.nil? ? "''" : __param_transform(var_name, 'Q')
      else value || ''
      end
    end

    # ${var/pattern/replacement} or ${var//pattern/replacement}
    # /  - replace first occurrence
    # // - replace all occurrences
    def __param_replace(var_name, operator, pattern, replacement)
      value = get_special_var(var_name) || Builtins.get_var(var_name) || ''
      return '' if value.empty?

      regex = pattern_to_regex(pattern, :any, :longest)
      replacement_proc = build_replacement_proc(replacement)

      case operator
      when '//' then replacement_proc ? value.gsub(regex, &replacement_proc) : value.gsub(regex, replacement)
      when '/' then replacement_proc ? value.sub(regex, &replacement_proc) : value.sub(regex, replacement)
      else value
      end
    end

    # Case modification operators
    # ^  - uppercase first character (if matches pattern)
    # ^^ - uppercase all characters (matching pattern)
    # ,  - lowercase first character (if matches pattern)
    # ,, - lowercase all characters (matching pattern)
    def __param_case(var_name, operator, pattern)
      value = Builtins.get_var(var_name) || ''
      return '' if value.empty?

      case operator
      when '^^' then apply_case_transform(value, pattern, :upcase, :all)
      when '^' then apply_case_transform(value, pattern, :upcase, :first)
      when ',,' then apply_case_transform(value, pattern, :downcase, :all)
      when ',' then apply_case_transform(value, pattern, :downcase, :first)
      else value
      end
    end

    # ${!var} - indirect expansion: get value of variable whose name is in var
    def __param_indirect(var_name)
      indirect_name = Builtins.get_var(var_name)
      return '' if indirect_name.nil? || indirect_name.empty?
      Builtins.get_var(indirect_name) || ''
    end

    # $"string" - locale-specific translation using TEXTDOMAIN
    # Uses gettext if available, otherwise returns original string
    def __translate(string)
      # noexpand_translation: do not expand $"..." strings for translation
      return string if Builtins.shopt_enabled?('noexpand_translation')

      textdomain = ENV['TEXTDOMAIN']
      return string if textdomain.nil? || textdomain.empty?

      begin
        require 'gettext'
        textdomaindir = ENV['TEXTDOMAINDIR']
        textdomaindir && !textdomaindir.empty? ? GetText.bindtextdomain(textdomain, path: textdomaindir) : GetText.bindtextdomain(textdomain)
        GetText._(string)
      rescue LoadError, StandardError
        string
      end
    end

    # ${arr[n]} or ${map[key]} - get array/assoc element
    # For associative arrays, index is expanded as string (key lookup)
    # For indexed arrays, index is evaluated as arithmetic expression
    def __array_element(var_name, index)
      expanded_index = expand_array_index(var_name, index)

      # Check special arrays first
      values = get_special_array_values(var_name)
      if values
        return get_special_assoc_value(var_name, expanded_index) if values == :assoc
        idx = safe_eval_index(expanded_index)
        return (values[idx] || '').to_s
      end

      if Builtins.assoc_array?(var_name)
        Builtins.get_assoc_element(var_name, expanded_index)
      else
        Builtins.get_array_element(var_name, safe_eval_index(expanded_index))
      end
    end

    # ${arr[@]} or ${arr[*]} - get all array/assoc values
    # @ mode: elements joined by space
    # * mode: elements joined by first character of IFS
    def __array_all(var_name, mode)
      values = get_special_array_values(var_name)
      values = case values
               when Array then values.map(&:to_s)
               when :assoc then get_special_assoc_all_values(var_name)
               when nil
                 if Builtins.assoc_array?(var_name)
                   Builtins.assoc_values(var_name)
                 else
                   Builtins.get_array(var_name).compact
                 end
               else values
               end

      mode == '@' ? values.join(' ') : Builtins.join_by_ifs(values)
    end

    # ${#arr[@]} - get array/assoc length
    def __array_length(var_name)
      values = get_special_array_values(var_name)
      length = case values
               when Array then values.length
               when :assoc then get_special_assoc_length(var_name)
               when nil
                 Builtins.assoc_array?(var_name) ? Builtins.assoc_length(var_name) : Builtins.array_length(var_name)
               else values.length
               end
      length.to_s
    end

    # ${!arr[@]} - get array indices or assoc keys
    def __array_keys(var_name)
      values = get_special_array_values(var_name)
      keys = case values
             when Array then (0...values.length).to_a
             when :assoc then get_special_assoc_keys(var_name)
             when nil
               if Builtins.assoc_array?(var_name)
                 Builtins.assoc_keys(var_name)
               else
                 arr = Builtins.get_array(var_name)
                 arr.each_index.select { |i| !arr[i].nil? }
               end
             else (0...values.length).to_a
             end
      keys.join(' ')
    end

    # === REPL methods ===

    def __cmd(name, *args, __prefix_env: nil, &block)
      cmd = Command.new(name, *args, &block)
      cmd.prefix_env = __prefix_env if __prefix_env
      cmd
    end

    def __and_cmd(left_proc, right_proc)
      left = __run_cmd(&left_proc)
      # Use @last_status to check success (handles function calls and builtins)
      return left unless @last_status == 0

      __run_cmd(&right_proc)
    end

    def __or_cmd(left_proc, right_proc)
      left = __run_cmd(&left_proc)
      # Use @last_status to check success (handles function calls and builtins)
      return left if @last_status == 0

      __run_cmd(&right_proc)
    end

    def __background(&block)
      # Wait if CHILD_MAX limit is reached
      JobManager.instance.wait_for_child_slot if Builtins.set_option?('m')

      # Fork and run in background
      pid = fork do
        # Reset signal handlers in child
        Kernel.trap('INT', 'DEFAULT')
        Kernel.trap('TSTP', 'DEFAULT')

        # Create new process group if job control is enabled
        Process.setpgid(0, 0) if Builtins.set_option?('m')

        # Execute the command
        result = block.call
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)
        Kernel.exit(0)
      end

      @last_bg_pid = pid

      # Only track jobs if monitor mode is enabled
      if Builtins.set_option?('m')
        Process.setpgid(pid, pid) rescue nil  # May fail if child already set it
        job = JobManager.instance.add(
          pid: pid,
          pgid: pid,
          command: @last_line
        )
        puts "[#{job.id}] #{pid}"
      else
        puts "[1] #{pid}"
      end
      nil
    end

    # Handle {varname} redirection syntax: exec {fd}>file
    # Allocates a file descriptor >= 10 and stores it in the named variable
    def __varname_redirect(varname, operator, target, &block)
      # Allocate a new FD number (>= 10, avoiding conflicts)
      fd_num = allocate_varname_fd

      # Store the FD number in the variable
      Builtins.set_var(varname, fd_num.to_s)

      # Track this FD for potential auto-closing
      @varname_fds[varname] = {fd: fd_num, target: target, operator: operator}

      # Now perform the actual redirection
      case operator
      when '>'
        # Open file for writing, associate with fd_num
        io = File.open(expand_single_arg(target), 'w')
        perform_varname_redirect(fd_num, io, &block)
      when '>>'
        # Open file for appending
        io = File.open(expand_single_arg(target), 'a')
        perform_varname_redirect(fd_num, io, &block)
      when '<'
        # Open file for reading
        io = File.open(expand_single_arg(target), 'r')
        perform_varname_redirect(fd_num, io, &block)
      when '>&'
        # Duplicate output FD
        src_fd = target.to_i
        perform_fd_dup(fd_num, src_fd, &block)
      when '<&'
        # Duplicate input FD
        src_fd = target.to_i
        perform_fd_dup(fd_num, src_fd, &block)
      else
        block.call
      end
    ensure
      # If varredir_close is enabled, close the FD after command completes
      if Builtins.shopt_enabled?('varredir_close') && @varname_fds[varname]
        close_varname_fd(varname)
      end
    end

    # Redirect output for compound commands (loops, conditionals, etc.)
    def __with_redirect(operator, target)
      case operator
      when '>'
        # Check noclobber: if set and file exists, fail
        if Builtins.set_option?('C') && File.exist?(target)
          $stderr.puts "rubish: #{target}: cannot overwrite existing file"
          return ExitStatus.new(1)
        end
        __with_stdout_redirect(target, 'w') { yield }
      when '>|'
        # Force overwrite even with noclobber
        __with_stdout_redirect(target, 'w') { yield }
      when '>>'
        __with_stdout_redirect(target, 'a') { yield }
      when '<'
        __with_stdin_redirect(target) { yield }
      when '2>'
        __with_stderr_redirect(target) { yield }
      else
        yield
      end
    end

    def __with_stdout_redirect(file, mode)
      old_stdout = $stdout
      begin
        $stdout = File.open(file, mode)
        yield
      ensure
        $stdout.close unless $stdout == old_stdout || $stdout.closed?
        $stdout = old_stdout
      end
    end

    def __with_stdin_redirect(file)
      old_stdin = $stdin
      begin
        $stdin = File.open(file, 'r')
        yield
      ensure
        $stdin.close unless $stdin == old_stdin || $stdin.closed?
        $stdin = old_stdin
      end
    end

    def __with_stderr_redirect(file)
      old_stderr = $stderr
      begin
        $stderr = File.open(file, 'w')
        yield
      ensure
        $stderr.close unless $stderr == old_stderr || $stderr.closed?
        $stderr = old_stderr
      end
    end

    def __condition(&block)
      result = block.call
      if result.is_a?(Command) && Builtins.builtin?(result.name)
        # Run builtin directly and check its return value
        Builtins.run(result.name, result.args)
      else
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)
        result.success?
      end
    end

    def __ruby_condition(expression)
      # Evaluate Ruby expression with shell variables bound as locals
      # VAR=foo becomes var = 'foo' in the Ruby binding
      # Use __binding__ to avoid conflicts with shell variable names
      __binding__ = binding
      __bound_vars__ = Set.new

      # First bind shell variables (these take precedence, includes function-local vars)
      Builtins.current_state.shell_vars.each do |key, value|
        var_name = key.downcase
        next unless var_name =~ /\A[a-z_][a-z0-9_]*\z/
        __binding__.local_variable_set(var_name.to_sym, value)
        __bound_vars__ << var_name
      end

      # Then bind ENV variables (inherited environment, unless already bound from shell_vars)
      ENV.each do |key, value|
        var_name = key.downcase
        next unless var_name =~ /\A[a-z_][a-z0-9_]*\z/
        next if __bound_vars__.include?(var_name)
        __binding__.local_variable_set(var_name.to_sym, value)
      end

      __binding__.eval(expression)
    end

    def __for_loop(variable, items, &block)
      items.each do |item|
        Builtins.set_var(variable, item)
        block.call
      end
    end

    def __each_loop(variable, source_lambda, body_code, &block)
      # Each loop: cmd.each {|var| body }
      # Captures output from source command and iterates over each line
      read_io, write_io = IO.pipe

      pid = fork do
        read_io.close
        $stdout.reopen(write_io)
        write_io.close

        # Call the lambda which creates a Command/Pipeline object
        result = source_lambda.call

        # Run the command if it's a Command or Pipeline
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)

        Kernel.exit(0)
      end

      write_io.close

      # Read output line by line and yield to block
      read_io.each_line do |line|
        block.call(line.chomp)
      end

      read_io.close
      Process.wait(pid)
    end

    def __eval_shell_code(code_string)
      # Parse and execute shell code string
      return if code_string.nil? || code_string.empty?

      tokens = Lexer.new(code_string).tokenize
      return if tokens.empty?

      ast = Parser.new(tokens).parse
      return unless ast

      code = Codegen.new.generate(ast)
      eval_in_context(code)
    end

    def __select_loop(variable, items, &block)
      return if items.empty?

      # Display menu once at start
      display_select_menu(items)

      loop do
        # Get PS3 prompt (default "#? ")
        # PS3 supports the same escape sequences as PS1
        ps3 = ENV['PS3'] || '#? '
        expanded_prompt = expand_prompt(ps3)
        print expanded_prompt

        # Read user input
        reply = $stdin.gets
        break unless reply  # EOF

        reply = reply.chomp
        Builtins.set_var('REPLY', reply)

        # Parse selection
        if reply =~ /\A\d+\z/
          num = reply.to_i
          if num >= 1 && num <= items.length
            Builtins.set_var(variable, items[num - 1])
          else
            Builtins.set_var(variable, '')
          end
        else
          Builtins.set_var(variable, '')
        end

        # Execute body
        block.call
      end
    end

    def __fetch_var(var_name)
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
      return monoseconds.to_s if var_name == 'RUBISH_MONOSECONDS' || var_name == 'BASH_MONOSECONDS'
      return argv0 if var_name == 'BASH_ARGV0' && !@bash_argv0_unset
      return Rubish::VERSION if var_name == 'RUBISH_VERSION'
      return Rubish::VERSION if var_name == 'BASH_VERSION'
      return ostype if var_name == 'OSTYPE'
      return hosttype if var_name == 'HOSTTYPE'
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
      return Builtins.bashopts if var_name == 'BASHOPTS'
      return Builtins.bash_compat if var_name == 'BASH_COMPAT'
      return ENV['RUBISH_EXECUTION_STRING'] || '' if var_name == 'RUBISH_EXECUTION_STRING' || var_name == 'BASH_EXECUTION_STRING'
      return rubish_path if var_name == 'RUBISH' || var_name == 'BASH'
      return Builtins.current_state.current_trapsig || '' if var_name == 'RUBISH_TRAPSIG' || var_name == 'BASH_TRAPSIG'
      return Builtins.readline_line if var_name == 'READLINE_LINE'
      return Builtins.readline_point.to_s if var_name == 'READLINE_POINT'
      return Builtins.readline_mark.to_s if var_name == 'READLINE_MARK'

      # Check if it's an array variable - join with space for string context
      if Builtins.array?(var_name)
        return Builtins.get_array(var_name).join(' ')
      end

      # Fetch variable with nounset check
      if Builtins.set_option?('u') && !Builtins.var_set?(var_name)
        $stderr.puts Builtins.format_error('unbound variable', command: var_name)
        raise NounsetError, "#{var_name}: unbound variable"
      end
      Builtins.get_var(var_name) || ''
    end

    # Fetch variable for use as command argument (quoted context)
    # Returns array if variable is an array (for proper expansion)
    # Returns string otherwise (empty string is preserved as "$var" keeps empty strings)
    def __fetch_var_for_arg(var_name)
      # Check if it's an array variable first
      if Builtins.array?(var_name)
        return Builtins.get_array(var_name)
      end

      # Otherwise fetch as regular variable
      __fetch_var(var_name)
    end

    # Fetch variable for use as command argument (unquoted context)
    # In bash, unquoted empty variable expansion is removed by word splitting
    # e.g., `cat $empty_var` becomes `cat` (no arguments), not `cat ""`
    # Returns array for proper flatten behavior - empty array if value is empty
    def __fetch_var_for_arg_unquoted(var_name)
      # Check if it's an array variable first
      if Builtins.array?(var_name)
        arr = Builtins.get_array(var_name)
        # Filter out empty strings from array expansion too
        return arr.reject(&:empty?)
      end

      # Otherwise fetch as regular variable
      value = __fetch_var(var_name)
      # Return empty array if value is nil or empty (so it gets removed from args)
      value.nil? || value.empty? ? [] : [value]
    end

    def __glob(pattern)
      # If noglob is set, return pattern as-is (no expansion)
      return [pattern] if Builtins.set_option?('f')

      # Handle VAR="value" or VAR='value' patterns: strip quotes from value
      # This is needed for commands like: env VAR="value" cmd
      if pattern =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)=(["'])(.*)\2\z/
        var_name = $1
        value = $3
        return ["#{var_name}=#{value}"]
      end

      # Handle globstar: ** matches directories recursively only when enabled
      # When disabled, treat ** as * (non-recursive)
      glob_pattern = if pattern.include?('**') && !Builtins.shopt_enabled?('globstar')
                       pattern.gsub('**', '*')
                     else
                       pattern
                     end

      # globasciiranges: when disabled, expand letter ranges to include both cases
      # (approximates locale-aware collation where a-z might include A-Z)
      unless Builtins.shopt_enabled?('globasciiranges')
        glob_pattern = expand_locale_ranges(glob_pattern)
      end

      # Expand POSIX character classes (e.g., [[:digit:]] -> [0-9])
      glob_pattern = expand_posix_classes(glob_pattern)

      # Expand glob pattern, return original if no matches (unless nullglob)
      # Check for extended globs if extglob is enabled
      # Build glob flags based on options
      glob_flags = 0
      glob_flags |= File::FNM_DOTMATCH if Builtins.shopt_enabled?('dotglob')
      glob_flags |= File::FNM_CASEFOLD if Builtins.shopt_enabled?('nocaseglob')

      if Builtins.shopt_enabled?('extglob') && has_extglob?(glob_pattern)
        matches = expand_extglob(glob_pattern)
      else
        matches = Dir.glob(glob_pattern, glob_flags)
      end

      # Filter out . and .. when dotglob is enabled or globskipdots is set
      if Builtins.shopt_enabled?('dotglob') || Builtins.shopt_enabled?('globskipdots')
        matches = matches.reject { |m| m.end_with?('/.') || m.end_with?('/..') || m == '.' || m == '..' }
      end

      # Apply GLOBIGNORE filtering
      matches = apply_globignore(matches)

      # Apply GLOBSORT sorting
      matches = apply_globsort(matches)

      if matches.empty?
        # Try abbreviated path expansion: l/r/repl.rb -> lib/rubish/repl.rb
        if pattern.include?('/') && !pattern.match?(/[*?\[\]]/)
          expanded = expand_abbreviated_path(pattern)
          return [expanded] if expanded && File.exist?(expanded)
        end

        if Builtins.shopt_enabled?('failglob')
          # failglob: patterns matching nothing cause an error
          $stderr.puts Builtins.format_error("no match: #{pattern}")
          raise FailglobError, "no match: #{pattern}"
        elsif Builtins.shopt_enabled?('nullglob')
          # nullglob: patterns matching nothing expand to nothing
          []
        else
          [pattern]
        end
      else
        matches
      end
    end

    def __proc_sub(command, direction)
      # Process substitution: <(cmd) or >(cmd)
      # Creates a named pipe and returns its path
      # The command runs in background, reading from or writing to the pipe

      # Create a unique FIFO path
      fifo_path = File.join(Dir.tmpdir, "rubish_procsub_#{$$}_#{rand(1000000)}")
      system('mkfifo', fifo_path)

      # Track the FIFO for cleanup
      @proc_sub_fifos ||= []
      @proc_sub_fifos << fifo_path

      if direction == :in
        # <(cmd) - command output becomes readable file
        # Fork a process to run the command and write to FIFO
        pid = fork do
          # Redirect stdout to the FIFO
          fifo = File.open(fifo_path, 'w')
          $stdout.reopen(fifo)
          $stderr.reopen('/dev/null', 'w')

          begin
            execute(command, skip_history_expansion: true)
            Kernel.exit(@last_status || 0)
          rescue => e
            $stderr.puts "rubish: #{e.message}"
            Kernel.exit(1)
          end
        end
        Process.detach(pid)
      else
        # >(cmd) - writable file whose content goes to command stdin
        # Fork a process to read from FIFO and pipe to command
        pid = fork do
          # Read from FIFO and pipe to command
          fifo = File.open(fifo_path, 'r')
          $stdin.reopen(fifo)
          $stderr.reopen('/dev/null', 'w')

          begin
            execute(command, skip_history_expansion: true)
            Kernel.exit(@last_status || 0)
          rescue => e
            $stderr.puts "rubish: #{e.message}"
            Kernel.exit(1)
          end
        end
        Process.detach(pid)
      end

      fifo_path
    end

    def __brace(pattern)
      # Expand brace patterns like {a,b,c} or {1..5}
      # Only expand if braceexpand option is enabled
      return [pattern] unless Builtins.set_option?('B')

      expand_braces(pattern)
    end

    def __case_match(pattern, word)
      # Shell pattern matching using fnmatch
      # Supports *, ?, [...] patterns
      flags = File::FNM_EXTGLOB
      flags |= File::FNM_CASEFOLD if Builtins.shopt_enabled?('nocasematch')
      File.fnmatch(pattern, word, flags)
    end

    def __subshell(&block)
      # Create a Subshell object that can be run, redirected, or piped
      # Wrap the block to increment subshell level before executing (in the forked process)
      Subshell.new do
        @subshell_level += 1
        block.call
      end
    end

    def __negate(&block)
      # Run command and negate exit status
      result = block.call

      # Handle different return types
      case result
      when Command, Pipeline, Subshell
        result.run unless result.ran?
        status = result.success?
      when ExitStatus
        status = result.success?
      when true, false
        status = result
      when Integer
        status = result == 0
      else
        status = result ? true : false
      end

      # Return negated status
      ExitStatus.new(status ? 1 : 0)
    end

    def __heredoc(delimiter, expand, strip_tabs, &block)
      content = @heredoc_content || ''

      # Apply tab stripping if <<- was used
      if strip_tabs
        content = content.lines.map { |l| l.sub(/\A\t+/, '') }.join
      end

      # Apply variable expansion if not quoted
      if expand
        content = expand_heredoc_content(content)
      end

      # Return a HeredocCommand that can be redirected and run later
      HeredocCommand.new(content, &block)
    end

    def __herestring(string, &block)
      # Herestring provides a single string as stdin (with trailing newline)
      content = "#{string}\n"

      # Return a HeredocCommand that can be redirected and run later
      HeredocCommand.new(content, &block)
    end

    # Thread-safe lazy_load for eval "$(cmd)" pattern
    # Runs the command using Open3 (no fork from thread)
    def __lazy_load_eval(cmd)
      require_relative 'lazy_loader'

      LazyLoader.register(cmd, @state.executor) do
        # Run command using Open3 - thread-safe, no fork issues
        output, status = Open3.capture2(cmd)
        output.chomp
      end

      true
    end

    # Generic lazy_load for arbitrary blocks (may hang if block uses fork)
    def __lazy_load(&block)
      require_relative 'lazy_loader'

      # Derive name from caller location
      caller_loc = caller_locations(1, 1).first
      name = if caller_loc
               "#{File.basename(caller_loc.path)}:#{caller_loc.lineno}"
             else
               'lazy'
             end

      LazyLoader.register(name, @state.executor) do
        # Execute the block - it returns generated code result
        result = block.call

        # Handle the result based on type
        if result.is_a?(Command) && result.name == 'eval' && result.args.any?
          # For eval "$(cmd)" - the args contain the output to be eval'd
          # Return the first arg as shell code to execute in main thread
          result.args.first.to_s
        elsif result.is_a?(String)
          # Direct string result - execute as shell code
          result
        else
          # For other commands, run them and capture stdout
          if result.respond_to?(:run)
            old_stdout = $stdout
            captured = StringIO.new
            begin
              $stdout = captured
              result.run
            ensure
              $stdout = old_stdout
            end
            output = captured.string
            output.empty? ? nil : output
          else
            nil
          end
        end
      end

      true
    end

    def __coproc(name, &block)
      # Check if a coproc with this name already exists
      if Builtins.coproc?(name)
        $stderr.puts "rubish: coproc #{name}: already exists"
        return ExitStatus.new(1)
      end

      # Create bidirectional pipes
      # parent_read/child_write: child writes stdout, parent reads
      # child_read/parent_write: parent writes, child reads stdin
      parent_read, child_write = IO.pipe
      child_read, parent_write = IO.pipe

      pid = fork do
        # Child process
        parent_read.close
        parent_write.close

        # Redirect stdin/stdout
        $stdin.reopen(child_read)
        $stdout.reopen(child_write)
        child_read.close
        child_write.close

        # Reset signal handlers
        Kernel.trap('INT', 'DEFAULT')
        Kernel.trap('TSTP', 'DEFAULT')

        # Execute the command
        result = block.call
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)
        Kernel.exit(result.respond_to?(:success?) && result.success? ? 0 : 1)
      end

      # Parent process
      child_read.close
      child_write.close

      # Store the coproc info
      Builtins.set_coproc(
        name,
        pid: pid,
        read_fd: parent_read.fileno,
        write_fd: parent_write.fileno,
        reader: parent_read,
        writer: parent_write
      )

      @last_bg_pid = pid
      puts "[coproc] #{name} #{pid}"

      ExitStatus.new(0)
    end

    def __time(posix_format = false, &block)
      # Measure execution time of a command
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      start_times = Process.times

      result = nil
      begin
        result = block.call
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)
      rescue => e
        $stderr.puts "rubish: time: #{e.message}"
      end

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end_times = Process.times

      # Calculate times
      real = end_time - start_time
      user = (end_times.utime - start_times.utime) + (end_times.cutime - start_times.cutime)
      sys = (end_times.stime - start_times.stime) + (end_times.cstime - start_times.cstime)

      # Output timing information to stderr
      if posix_format
        # POSIX format: seconds with fractions
        $stderr.puts format('real %.2f', real)
        $stderr.puts format('user %.2f', user)
        $stderr.puts format('sys %.2f', sys)
      elsif ENV['TIMEFORMAT']
        # Custom TIMEFORMAT
        output = format_timeformat(ENV['TIMEFORMAT'], real, user, sys)
        $stderr.puts output unless output.empty?
      else
        # Default bash-like format
        $stderr.puts
        $stderr.puts format("real\t%dm%.3fs", (real / 60).to_i, real % 60)
        $stderr.puts format("user\t%dm%.3fs", (user / 60).to_i, user % 60)
        $stderr.puts format("sys\t%dm%.3fs", (sys / 60).to_i, sys % 60)
      end

      # Return the result's exit status
      if result.respond_to?(:status) && result.status
        # Command/Pipeline with status
        result.status.success? ? ExitStatus.new(0) : ExitStatus.new(result.status.exitstatus || 1)
      elsif result.respond_to?(:success?)
        result.success? ? ExitStatus.new(0) : ExitStatus.new(1)
      else
        ExitStatus.new(0)
      end
    end

    def __cond_test(parts)
      # Evaluate [[ ]] conditional expression
      # Returns ExitStatus based on expression result
      result = eval_cond_expr(parts, 0, parts.length)
      ExitStatus.new(result ? 0 : 1)
    end

    def __array_assign(var_part, elements)
      # Handle array assignment: VAR=(a b c) or VAR+=(d e)
      # var_part includes the = or +=, e.g., "arr=" or "arr+="

      if var_part.end_with?('+=')
        # Append: arr+=(d e)
        var_name = var_part.chomp('+=')
        array_append(var_name, elements)
      else
        # Assign: arr=(a b c)
        var_name = var_part.chomp('=')
        set_array(var_name, elements)
      end

      ExitStatus.new(0)
    end

    def __define_function(name, source_code = nil, params = nil, &block)
      @functions[name] = {block: block, source: @current_source_file, source_code: source_code, lineno: @lineno, params: params}
      nil
    end

    # Builtins that must run in current process (affect shell state)
    PROCESS_BUILTINS = %w[cd export set shift source . return exit break continue local unset readonly declare typeset let eval command builtin shopt alias unalias trap].freeze

    def __run_cmd(&block)
      result = block.call

      # Run DEBUG trap before each command
      Builtins.debug_trap

      if result.is_a?(Command) && result.name == 'exec'
        # Special handling for exec builtin
        handle_exec_command(result)
        result
      elsif result.is_a?(Command) && PROCESS_BUILTINS.include?(result.name)
        # Run process-affecting builtins directly in current process
        success = Builtins.run(result.name, result.args)
        @last_status = success ? 0 : 1
        run_err_trap_if_failed
        check_errexit
        # Return ExitStatus to prevent eval_in_context from trying to run command again
        ExitStatus.new(@last_status)
      elsif result.is_a?(Command) && Builtins.builtin?(result.name) && !result.stdout && !result.stderr
        # Run builtins without explicit redirects in current process
        # This allows them to respect $stdout set by __with_redirect for compound commands
        success = Builtins.run(result.name, result.args)
        @last_status = success ? 0 : 1
        run_err_trap_if_failed
        check_errexit
        # Return ExitStatus so callers (like Subshell) know the real exit status
        ExitStatus.new(@last_status)
      elsif result.is_a?(Command) && @functions.key?(result.name)
        # Call user-defined function with redirects
        call_function_with_redirects(result)
        # Don't run ERR trap here - it was already handled inside the function
        check_errexit
        result
      elsif result.is_a?(Command) && bare_assignment?(result.name) && result.args.all? { |a| bare_assignment?(a) }
        # Handle bare variable assignments in lists (VAR=value)
        handle_bare_assignments([result.name] + result.args)
        @last_status = 0
        result
      else
        result.run if result.is_a?(Command) || result.is_a?(Pipeline) || result.is_a?(Subshell)
        if result.respond_to?(:status)
          @last_status = result.status&.exitstatus || 0
          # Update PIPESTATUS array
          if result.is_a?(Pipeline) && result.statuses
            @pipestatus = result.statuses.map { |s| s.exitstatus || 0 }
          else
            @pipestatus = [@last_status]
          end
          run_err_trap_if_failed
          check_errexit
        elsif result.respond_to?(:exitstatus)
          # Handle ExitStatus objects (from __cond_test, etc.)
          @last_status = result.exitstatus || 0
          @pipestatus = [@last_status]
          run_err_trap_if_failed
          check_errexit
        end
        result
      end
    end
  end
end
