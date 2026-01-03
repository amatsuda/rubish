# frozen_string_literal: true

module Rubish
  module Builtins
    COMMANDS = %w(cd exit jobs fg bg export pwd history alias unalias source . shift set return read echo test [ break continue pushd popd dirs trap getopts local unset readonly).freeze

    @aliases = {}
    @dir_stack = []
    @traps = {}
    @original_traps = {}
    @local_scope_stack = []  # Stack of hashes for local variable scopes
    @readonly_vars = {}  # Hash of readonly variable names to their values
    @executor = nil
    @script_name_getter = nil
    @script_name_setter = nil
    @positional_params_getter = nil
    @positional_params_setter = nil
    @function_checker = nil
    @function_remover = nil
    @heredoc_content_setter = nil

    class << self
      attr_reader :aliases, :dir_stack, :traps, :local_scope_stack, :readonly_vars
      attr_accessor :executor, :script_name_getter, :script_name_setter, :positional_params_getter, :positional_params_setter, :function_checker, :function_remover, :heredoc_content_setter
    end

    def self.builtin?(name)
      COMMANDS.include?(name)
    end

    def self.run(name, args)
      case name
      when 'cd'
        run_cd(args)
      when 'exit'
        run_exit(args)
      when 'jobs'
        run_jobs(args)
      when 'fg'
        run_fg(args)
      when 'bg'
        run_bg(args)
      when 'export'
        run_export(args)
      when 'pwd'
        run_pwd(args)
      when 'history'
        run_history(args)
      when 'alias'
        run_alias(args)
      when 'unalias'
        run_unalias(args)
      when 'source', '.'
        run_source(args)
      when 'shift'
        run_shift(args)
      when 'set'
        run_set(args)
      when 'return'
        run_return(args)
      when 'read'
        run_read(args)
      when 'echo'
        run_echo(args)
      when 'test', '['
        run_test(args)
      when 'break'
        run_break(args)
      when 'continue'
        run_continue(args)
      when 'pushd'
        run_pushd(args)
      when 'popd'
        run_popd(args)
      when 'dirs'
        run_dirs(args)
      when 'trap'
        run_trap(args)
      when 'getopts'
        run_getopts(args)
      when 'local'
        run_local(args)
      when 'unset'
        run_unset(args)
      when 'readonly'
        run_readonly(args)
      else
        false
      end
    end

    def self.run_cd(args)
      dir = args.first || ENV['HOME']
      Dir.chdir(dir)
      true
    rescue Errno::ENOENT => e
      puts "cd: #{e.message}"
      false
    end

    def self.run_pushd(args)
      if args.empty?
        # Swap top two directories
        if @dir_stack.empty?
          puts 'pushd: no other directory'
          return false
        end
        current = Dir.pwd
        target = @dir_stack.shift
        begin
          Dir.chdir(target)
          @dir_stack.unshift(current)
          print_dir_stack
          true
        rescue Errno::ENOENT => e
          puts "pushd: #{e.message}"
          false
        end
      else
        dir = args.first
        dir = File.expand_path(dir)
        current = Dir.pwd
        begin
          Dir.chdir(dir)
          @dir_stack.unshift(current)
          print_dir_stack
          true
        rescue Errno::ENOENT => e
          puts "pushd: #{e.message}"
          false
        end
      end
    end

    def self.run_popd(args)
      if @dir_stack.empty?
        puts 'popd: directory stack empty'
        return false
      end

      target = @dir_stack.shift
      begin
        Dir.chdir(target)
        print_dir_stack
        true
      rescue Errno::ENOENT => e
        puts "popd: #{e.message}"
        false
      end
    end

    def self.run_dirs(args)
      print_dir_stack
      true
    end

    def self.print_dir_stack
      stack = [Dir.pwd] + @dir_stack
      puts stack.map { |d| d.sub(ENV['HOME'], '~') }.join(' ')
    end

    def self.clear_dir_stack
      @dir_stack.clear
    end

    # Signal name mapping
    SIGNALS = {
      'EXIT' => 0,
      'HUP' => 'HUP', 'SIGHUP' => 'HUP',
      'INT' => 'INT', 'SIGINT' => 'INT',
      'QUIT' => 'QUIT', 'SIGQUIT' => 'QUIT',
      'TERM' => 'TERM', 'SIGTERM' => 'TERM',
      'USR1' => 'USR1', 'SIGUSR1' => 'USR1',
      'USR2' => 'USR2', 'SIGUSR2' => 'USR2',
      'ALRM' => 'ALRM', 'SIGALRM' => 'ALRM',
      'CHLD' => 'CHLD', 'SIGCHLD' => 'CHLD',
      'CONT' => 'CONT', 'SIGCONT' => 'CONT',
      'TSTP' => 'TSTP', 'SIGTSTP' => 'TSTP',
      'TTIN' => 'TTIN', 'SIGTTIN' => 'TTIN',
      'TTOU' => 'TTOU', 'SIGTTOU' => 'TTOU',
      'WINCH' => 'WINCH', 'SIGWINCH' => 'WINCH'
    }.freeze

    def self.run_trap(args)
      if args.empty?
        # List all traps
        @traps.each do |sig, cmd|
          sig_name = sig == 0 ? 'EXIT' : sig
          puts "trap -- #{cmd.inspect} #{sig_name}"
        end
        return true
      end

      # trap -l: list signal names
      if args.first == '-l'
        puts Signal.list.keys.sort.join(' ')
        return true
      end

      # trap -p [signal...]: print trap commands
      if args.first == '-p'
        signals = args[1..] || []
        if signals.empty?
          @traps.each do |sig, cmd|
            sig_name = sig == 0 ? 'EXIT' : sig
            puts "trap -- #{cmd.inspect} #{sig_name}"
          end
        else
          signals.each do |sig_arg|
            sig = normalize_signal(sig_arg)
            next unless sig

            if @traps.key?(sig)
              sig_name = sig == 0 ? 'EXIT' : sig
              puts "trap -- #{@traps[sig].inspect} #{sig_name}"
            end
          end
        end
        return true
      end

      # trap command signal [signal...]
      # trap '' signal - ignore signal
      # trap - signal - reset to default
      command = args.first
      signals = args[1..]

      if signals.nil? || signals.empty?
        puts 'trap: usage: trap [-lp] [[command] signal_spec ...]'
        return false
      end

      signals.each do |sig_arg|
        sig = normalize_signal(sig_arg)
        unless sig
          puts "trap: #{sig_arg}: invalid signal specification"
          next
        end

        if command == '-'
          # Reset to default
          reset_trap(sig)
        elsif command.empty? || command == ''
          # Ignore signal
          set_trap(sig, '')
        else
          # Set trap
          set_trap(sig, command)
        end
      end

      true
    end

    def self.normalize_signal(sig_arg)
      # Handle numeric signals
      if sig_arg =~ /\A\d+\z/
        return sig_arg.to_i
      end

      # Handle signal names
      sig_upper = sig_arg.upcase
      SIGNALS[sig_upper]
    end

    def self.set_trap(sig, command)
      # Store the trap command
      @traps[sig] = command

      # Handle EXIT specially - it's called when the shell exits
      return if sig == 0

      # Save original handler if not already saved
      @original_traps[sig] ||= Signal.trap(sig, 'DEFAULT') rescue nil

      if command.empty?
        # Ignore the signal
        Signal.trap(sig, 'IGNORE')
      else
        # Set up the handler
        Signal.trap(sig) do
          @executor&.call(command) if @executor
        end
      end
    rescue ArgumentError => e
      puts "trap: #{e.message}"
    end

    def self.reset_trap(sig)
      @traps.delete(sig)

      return if sig == 0

      # Restore original handler
      if @original_traps.key?(sig)
        Signal.trap(sig, @original_traps.delete(sig) || 'DEFAULT')
      else
        Signal.trap(sig, 'DEFAULT')
      end
    rescue ArgumentError => e
      puts "trap: #{e.message}"
    end

    def self.run_exit_traps
      return unless @traps.key?(0)

      @executor&.call(@traps[0]) if @executor
    end

    def self.clear_traps
      @traps.each_key do |sig|
        reset_trap(sig) unless sig == 0
      end
      @traps.clear
      @original_traps.clear
    end

    def self.run_getopts(args)
      # getopts optstring name [args...]
      # Returns true if option found, false when done
      if args.length < 2
        puts 'getopts: usage: getopts optstring name [arg ...]'
        return false
      end

      optstring = args[0]
      varname = args[1]

      # Get arguments to parse - either from args or positional params
      if args.length > 2
        parse_args = args[2..]
      else
        parse_args = @positional_params_getter&.call || []
      end

      # Get current OPTIND (1-based index)
      optind = (ENV['OPTIND'] || '1').to_i

      # Check if we're done
      if optind > parse_args.length
        ENV[varname] = '?'
        return false
      end

      # Get current argument
      arg = parse_args[optind - 1]

      # Check if it's an option
      if arg.nil? || arg == '--' || !arg.start_with?('-') || arg == '-'
        ENV[varname] = '?'
        return false
      end

      # Handle -- to stop option processing
      if arg == '--'
        ENV['OPTIND'] = (optind + 1).to_s
        ENV[varname] = '?'
        return false
      end

      # Get the current character position within the option group
      # OPTPOS tracks position in grouped options like -abc
      optpos = (ENV['_OPTPOS'] || '1').to_i

      opt_char = arg[optpos]

      # Check if this is a valid option
      opt_idx = optstring.index(opt_char)
      silent_errors = optstring.start_with?(':')

      if opt_idx.nil?
        # Invalid option
        ENV[varname] = '?'
        ENV['OPTARG'] = opt_char if silent_errors
        unless silent_errors
          puts "getopts: illegal option -- #{opt_char}"
        end
        # Move to next character or next argument
        if optpos + 1 < arg.length
          ENV['_OPTPOS'] = (optpos + 1).to_s
        else
          ENV['OPTIND'] = (optind + 1).to_s
          ENV['_OPTPOS'] = '1'
        end
        return true
      end

      # Check if option requires an argument
      requires_arg = optstring[opt_idx + 1] == ':'

      if requires_arg
        # Check for argument
        if optpos + 1 < arg.length
          # Argument is rest of current arg (e.g., -ovalue)
          ENV['OPTARG'] = arg[(optpos + 1)..]
          ENV['OPTIND'] = (optind + 1).to_s
          ENV['_OPTPOS'] = '1'
        elsif optind < parse_args.length
          # Argument is next arg
          ENV['OPTARG'] = parse_args[optind]
          ENV['OPTIND'] = (optind + 2).to_s
          ENV['_OPTPOS'] = '1'
        else
          # Missing argument
          if silent_errors
            ENV[varname] = ':'
            ENV['OPTARG'] = opt_char
          else
            ENV[varname] = '?'
            puts "getopts: option requires an argument -- #{opt_char}"
          end
          ENV['OPTIND'] = (optind + 1).to_s
          ENV['_OPTPOS'] = '1'
          return true
        end
      else
        # No argument required
        ENV.delete('OPTARG')
        # Move to next character or next argument
        if optpos + 1 < arg.length
          ENV['_OPTPOS'] = (optpos + 1).to_s
        else
          ENV['OPTIND'] = (optind + 1).to_s
          ENV['_OPTPOS'] = '1'
        end
      end

      ENV[varname] = opt_char
      true
    end

    def self.reset_getopts
      ENV['OPTIND'] = '1'
      ENV['_OPTPOS'] = '1'
      ENV.delete('OPTARG')
    end

    def self.run_local(args)
      # local var=value or local var
      # Only valid inside a function (when scope stack is not empty)
      if @local_scope_stack.empty?
        puts 'local: can only be used in a function'
        return false
      end

      current_scope = @local_scope_stack.last

      args.each do |arg|
        if arg.include?('=')
          name, value = arg.split('=', 2)
          # Check if readonly
          if readonly?(name)
            puts "local: #{name}: readonly variable"
            next
          end
          # Save original value if not already in this scope
          unless current_scope.key?(name)
            current_scope[name] = ENV.key?(name) ? ENV[name] : :unset
          end
          ENV[name] = value
        else
          # Just declare as local without value
          unless current_scope.key?(arg)
            current_scope[arg] = ENV.key?(arg) ? ENV[arg] : :unset
          end
          # Don't change the value, just mark it as local
        end
      end

      true
    end

    def self.push_local_scope
      @local_scope_stack.push({})
    end

    def self.pop_local_scope
      return if @local_scope_stack.empty?

      scope = @local_scope_stack.pop
      # Restore original values
      scope.each do |name, original_value|
        if original_value == :unset
          ENV.delete(name)
        else
          ENV[name] = original_value
        end
      end
    end

    def self.in_function?
      !@local_scope_stack.empty?
    end

    def self.clear_local_scopes
      @local_scope_stack.clear
    end

    def self.run_unset(args)
      # unset [-fv] name [name ...]
      # -f: treat names as function names
      # -v: treat names as variable names (default)
      mode = :variable  # default mode

      if args.empty?
        puts 'unset: usage: unset [-f] [-v] name [name ...]'
        return false
      end

      names = []
      args.each do |arg|
        case arg
        when '-f'
          mode = :function
        when '-v'
          mode = :variable
        when '-fv', '-vf'
          # Last one wins in bash, but typically -v is ignored when -f present
          mode = :function
        else
          names << arg
        end
      end

      if names.empty?
        puts 'unset: usage: unset [-f] [-v] name [name ...]'
        return false
      end

      names.each do |name|
        if mode == :function
          # Remove function
          @function_remover&.call(name)
        else
          # Check if readonly
          if readonly?(name)
            puts "unset: #{name}: readonly variable"
            next
          end
          # Remove environment variable
          ENV.delete(name)
        end
      end

      true
    end

    def self.run_readonly(args)
      # readonly [-p] [name[=value] ...]
      # -p: print all readonly variables in reusable format

      if args.empty? || args == ['-p']
        # List all readonly variables
        @readonly_vars.each do |name, _|
          value = ENV[name]
          if value
            puts "readonly #{name}=#{value.inspect}"
          else
            puts "readonly #{name}"
          end
        end
        return true
      end

      # Filter out -p flag
      names = args.reject { |a| a == '-p' }

      names.each do |arg|
        if arg.include?('=')
          name, value = arg.split('=', 2)
          # Check if already readonly with different value
          if @readonly_vars.key?(name) && ENV[name] != value
            puts "readonly: #{name}: readonly variable"
            next
          end
          ENV[name] = value
          @readonly_vars[name] = true
        else
          # Mark existing variable as readonly
          @readonly_vars[arg] = true
        end
      end

      true
    end

    def self.readonly?(name)
      @readonly_vars.key?(name)
    end

    def self.clear_readonly_vars
      @readonly_vars.clear
    end

    def self.run_export(args)
      if args.empty?
        # List all environment variables
        ENV.each { |k, v| puts "#{k}=#{v}" }
      else
        args.each do |arg|
          if arg.include?('=')
            key, value = arg.split('=', 2)
            if readonly?(key)
              puts "export: #{key}: readonly variable"
              next
            end
            ENV[key] = value
          else
            # Just export existing variable (no-op in this simple impl)
            puts "export: #{arg}=#{ENV[arg]}" if ENV.key?(arg)
          end
        end
      end
      true
    end

    def self.run_pwd(_args)
      puts Dir.pwd
      true
    end

    def self.run_history(args)
      history = Reline::HISTORY.to_a
      count = args.first&.to_i || history.length

      start_index = [history.length - count, 0].max
      history[start_index..].each_with_index do |line, i|
        puts format('%5d  %s', start_index + i + 1, line)
      end
      true
    end

    def self.run_alias(args)
      if args.empty?
        # List all aliases
        @aliases.each { |name, value| puts "alias #{name}='#{value}'" }
      else
        args.each do |arg|
          if arg.include?('=')
            name, value = arg.split('=', 2)
            # Remove surrounding quotes if present
            value = value.sub(/\A(['"])(.*)\1\z/, '\2')
            @aliases[name] = value
          else
            # Show specific alias
            if @aliases.key?(arg)
              puts "alias #{arg}='#{@aliases[arg]}'"
            else
              puts "alias: #{arg}: not found"
            end
          end
        end
      end
      true
    end

    def self.run_unalias(args)
      if args.empty?
        puts 'unalias: usage: unalias name [name ...]'
        return false
      end

      args.each do |name|
        if @aliases.key?(name)
          @aliases.delete(name)
        else
          puts "unalias: #{name}: not found"
        end
      end
      true
    end

    def self.expand_alias(line)
      return line if line.empty?

      # Extract the first word
      first_word = line.split(/\s/, 2).first
      return line unless first_word

      if @aliases.key?(first_word)
        rest = line[first_word.length..]
        "#{@aliases[first_word]}#{rest}"
      else
        line
      end
    end

    def self.clear_aliases
      @aliases.clear
    end

    def self.run_source(args)
      if args.empty?
        puts 'source: usage: source filename [arguments]'
        return false
      end

      file = args.first
      file = File.expand_path(file)

      unless File.exist?(file)
        puts "source: #{file}: No such file or directory"
        return false
      end

      unless @executor
        puts 'source: executor not configured'
        return false
      end

      # Save and set script name and positional params
      old_script_name = @script_name_getter&.call
      old_positional_params = @positional_params_getter&.call
      @script_name_setter&.call(file)
      @positional_params_setter&.call(args[1..] || [])

      return_code = catch(:return) do
        buffer = +''
        depth = 0
        lines = File.readlines(file, chomp: true)
        i = 0

        while i < lines.length
          line = lines[i].strip
          i += 1
          next if line.empty? || line.start_with?('#')

          # Check for heredoc in this line
          heredoc_info = detect_heredoc(line)
          if heredoc_info
            delimiter, strip_tabs = heredoc_info
            heredoc_lines = []
            # Collect heredoc content from subsequent lines
            while i < lines.length
              heredoc_line = lines[i]
              i += 1
              # Check for delimiter (possibly with leading tabs if strip_tabs)
              check_line = strip_tabs ? heredoc_line.sub(/\A\t+/, '') : heredoc_line
              if check_line.strip == delimiter
                break
              end
              heredoc_lines << heredoc_line
            end
            # Set heredoc content before executing
            content = heredoc_lines.join("\n") + (heredoc_lines.empty? ? '' : "\n")
            @heredoc_content_setter&.call(content)
          end

          # Track control structure depth
          words = line.split(/\s+/)
          words.each do |word|
            case word
            when 'if', 'while', 'until', 'for', 'case'
              depth += 1
            when 'fi', 'done', 'esac'
              depth -= 1
            when '{'
              depth += 1
            when '}'
              depth -= 1
            when '('
              # Standalone ( is a subshell
              depth += 1
            when ')'
              # Standalone ) closes a subshell
              depth -= 1
            end
          end

          # Accumulate lines
          if buffer.empty?
            buffer = line
          else
            buffer = "#{buffer}; #{line}"
          end

          # Execute when we have a complete statement
          if depth == 0
            begin
              @executor.call(buffer)
            rescue => e
              puts "source: #{e.message}"
            end
            buffer = +''
          end
        end

        # Execute any remaining buffer (incomplete statement)
        unless buffer.empty?
          begin
            @executor.call(buffer)
          rescue => e
            puts "source: #{e.message}"
          end
        end

        nil
      end

      # Restore script name and positional params
      @script_name_setter&.call(old_script_name) if old_script_name
      @positional_params_setter&.call(old_positional_params) if old_positional_params

      return_code.nil? || return_code == 0
    end

    def self.run_shift(args)
      n = args.first&.to_i || 1

      return false if n < 0

      params = @positional_params_getter&.call || []

      if n > params.length
        puts 'shift: shift count out of range'
        return false
      end

      @positional_params_setter&.call(params.drop(n))
      true
    end

    def self.run_set(args)
      # set -- arg1 arg2 arg3  sets positional params
      # set (no args) could list variables, but for now just clear params
      if args.empty?
        @positional_params_setter&.call([])
      elsif args.first == '--'
        @positional_params_setter&.call(args[1..] || [])
      else
        @positional_params_setter&.call(args)
      end
      true
    end

    def self.run_return(args)
      code = args.first&.to_i || 0
      throw :return, code
    end

    def self.run_break(args)
      # Optional: break N to break out of N levels (default 1)
      levels = args.first&.to_i || 1
      throw :break_loop, levels
    end

    def self.run_continue(args)
      # Optional: continue N to continue Nth enclosing loop (default 1)
      levels = args.first&.to_i || 1
      throw :continue_loop, levels
    end

    def self.run_test(args)
      # Remove trailing ] if called as [
      args = args[0...-1] if args.last == ']'

      return false if args.empty?

      # Unary operators
      if args.length == 2
        op, arg = args
        case op
        when '-z' then return arg.empty?
        when '-n' then return !arg.empty?
        when '-f' then return File.file?(arg)
        when '-d' then return File.directory?(arg)
        when '-e' then return File.exist?(arg)
        when '-r' then return File.readable?(arg)
        when '-w' then return File.writable?(arg)
        when '-x' then return File.executable?(arg)
        when '-s' then return File.exist?(arg) && File.size(arg) > 0
        end
      end

      # Single argument - true if non-empty
      return !args.first.empty? if args.length == 1

      # Binary operators
      if args.length == 3
        left, op, right = args
        case op
        when '=' then return left == right
        when '==' then return left == right
        when '!=' then return left != right
        when '-eq' then return left.to_i == right.to_i
        when '-ne' then return left.to_i != right.to_i
        when '-lt' then return left.to_i < right.to_i
        when '-le' then return left.to_i <= right.to_i
        when '-gt' then return left.to_i > right.to_i
        when '-ge' then return left.to_i >= right.to_i
        end
      end

      # Negation
      if args.first == '!'
        return !run_test(args[1..])
      end

      false
    end

    def self.run_echo(args)
      newline = true
      start_idx = 0

      if args.first == '-n'
        newline = false
        start_idx = 1
      end

      output = args[start_idx..].join(' ')

      if newline
        puts output
      else
        print output
      end

      true
    end

    def self.run_read(args)
      prompt = nil
      vars = []

      # Parse options
      i = 0
      while i < args.length
        if args[i] == '-p' && args[i + 1]
          prompt = args[i + 1]
          i += 2
        else
          vars << args[i]
          i += 1
        end
      end

      # Default variable is REPLY
      vars << 'REPLY' if vars.empty?

      # Display prompt if specified
      print prompt if prompt

      # Read line from stdin
      line = $stdin.gets
      return false unless line

      line = line.chomp
      words = line.split

      # Assign to variables
      vars.each_with_index do |var, idx|
        if idx == vars.length - 1
          # Last variable gets remaining words
          ENV[var] = (words[idx..] || []).join(' ')
        else
          ENV[var] = words[idx] || ''
        end
      end

      true
    end

    def self.run_exit(args)
      code = args.first&.to_i || 0
      run_exit_traps
      throw :exit, code
    end

    def self.run_jobs(_args)
      jobs = JobManager.instance.active
      if jobs.empty?
        # No output when no jobs
      else
        jobs.each { |job| puts job }
      end
      true
    end

    def self.run_fg(args)
      job = find_job(args)
      return false unless job

      puts job.command

      # Bring to foreground
      Process.kill('CONT', -job.pgid) if job.stopped?

      # Give terminal control to the job's process group
      begin
        # Wait for the job
        _, status = Process.wait2(job.pid, Process::WUNTRACED)

        if status.stopped?
          job.status = :stopped
          puts "\n[#{job.id}]  Stopped                 #{job.command}"
        else
          job.status = :done
          JobManager.instance.remove(job.id)
        end
      rescue Errno::ECHILD
        job.status = :done
        JobManager.instance.remove(job.id)
      end

      true
    end

    def self.run_bg(args)
      job = find_job(args)
      return false unless job

      unless job.stopped?
        puts "bg: job #{job.id} is not stopped"
        return false
      end

      job.status = :running
      Process.kill('CONT', -job.pgid)
      puts "[#{job.id}] #{job.command} &"
      true
    end

    def self.find_job(args)
      manager = JobManager.instance

      if args.empty?
        job = manager.last
        unless job
          puts 'fg: no current job'
          return nil
        end
        job
      else
        # Parse %n or just n
        id_str = args.first.to_s.delete_prefix('%')
        id = id_str.to_i
        job = manager.get(id)
        unless job
          puts "fg: %#{id}: no such job"
          return nil
        end
        job
      end
    end

    def self.detect_heredoc(line)
      # Detect heredoc in a line: <<WORD, <<-WORD, <<'WORD', <<"WORD"
      # Does not match herestrings (<<<)
      # Returns [delimiter, strip_tabs] or nil
      return nil unless line.include?('<<')
      return nil if line.include?('<<<')  # Skip herestrings

      # Match heredoc patterns
      # <<-'DELIM' or <<-"DELIM" or <<-DELIM (strip tabs)
      if line =~ /<<-\s*(['"])([^'"]+)\1/
        return [$2, true]
      elsif line =~ /<<-\s*([a-zA-Z_][a-zA-Z0-9_]*)/
        return [$1, true]
      # <<'DELIM' or <<"DELIM" or <<DELIM (no strip tabs)
      elsif line =~ /<<\s*(['"])([^'"]+)\1/
        return [$2, false]
      elsif line =~ /<<\s*([a-zA-Z_][a-zA-Z0-9_]*)/
        return [$1, false]
      end

      nil
    end
  end
end
