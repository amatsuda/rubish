# frozen_string_literal: true

module Rubish
  module Builtins
    COMMANDS = %w(cd exit logout jobs fg bg export pwd history alias unalias source . shift set return read echo test [ break continue pushd popd dirs trap getopts local unset readonly declare typeset let printf type which true false : eval command builtin wait kill umask exec times hash disown ulimit suspend shopt enable caller complete compgen compopt bind help fc mapfile readarray).freeze

    @aliases = {}
    @dir_stack = []
    @traps = {}
    @original_traps = {}
    @local_scope_stack = []  # Stack of hashes for local variable scopes
    @readonly_vars = {}  # Hash of readonly variable names to their values
    @var_attributes = {}  # Hash of variable names to Set of attributes (:integer, :lowercase, :uppercase, :export)
    @command_hash = {}  # Hash of command names to their cached paths
    @shell_options = {}  # Hash of shell option names to boolean values
    @disabled_builtins = Set.new  # Set of disabled builtin names
    @call_stack = []  # Stack of [line_number, function_name, filename] for caller builtin
    @completions = {}  # Hash of command names to completion specs
    @completion_options = {}  # Hash of command names to Set of completion options
    @current_completion_options = Set.new  # Options for currently executing completion
    @key_bindings = {}  # Hash of keyseq to function/macro/command
    @readline_variables = {}  # Hash of readline variable names to values
    @arrays = {}  # Hash of array variable names to their values (Array)
    @assoc_arrays = {}  # Hash of associative array names to their values (Hash)
    @coprocs = {}  # Hash of coproc names to {pid:, read_fd:, write_fd:, reader:, writer:}
    @executor = nil
    @script_name_getter = nil
    @script_name_setter = nil
    @positional_params_getter = nil
    @positional_params_setter = nil
    @function_checker = nil
    @function_remover = nil
    @heredoc_content_setter = nil
    @command_executor = nil  # Executor that bypasses functions/aliases

    class << self
      attr_reader :aliases, :dir_stack, :traps, :local_scope_stack, :readonly_vars, :var_attributes, :command_hash, :shell_options, :disabled_builtins, :call_stack, :completions, :completion_options, :key_bindings, :readline_variables, :arrays, :assoc_arrays, :coprocs
      attr_accessor :executor, :script_name_getter, :script_name_setter, :positional_params_getter, :positional_params_setter, :function_checker, :function_remover, :heredoc_content_setter, :command_executor, :current_completion_options
    end

    # Array variable methods
    def self.array?(name)
      @arrays.key?(name)
    end

    def self.get_array(name)
      @arrays[name] || []
    end

    def self.set_array(name, values)
      @arrays[name] = values.is_a?(Array) ? values : [values]
    end

    def self.get_array_element(name, index)
      arr = @arrays[name]
      return '' unless arr
      arr[index.to_i] || ''
    end

    def self.set_array_element(name, index, value)
      @arrays[name] ||= []
      @arrays[name][index.to_i] = value
    end

    def self.array_length(name)
      (@arrays[name] || []).length
    end

    def self.array_append(name, values)
      @arrays[name] ||= []
      @arrays[name].concat(values.is_a?(Array) ? values : [values])
    end

    def self.unset_array(name)
      @arrays.delete(name)
    end

    def self.unset_array_element(name, index)
      return unless @arrays[name]
      @arrays[name][index.to_i] = nil
    end

    # Associative array methods
    def self.assoc_array?(name)
      @assoc_arrays.key?(name)
    end

    def self.declare_assoc_array(name)
      @assoc_arrays[name] ||= {}
    end

    def self.get_assoc_array(name)
      @assoc_arrays[name] || {}
    end

    def self.set_assoc_array(name, hash)
      @assoc_arrays[name] = hash.is_a?(Hash) ? hash : {}
    end

    def self.get_assoc_element(name, key)
      hash = @assoc_arrays[name]
      return '' unless hash
      hash[key] || ''
    end

    def self.set_assoc_element(name, key, value)
      @assoc_arrays[name] ||= {}
      @assoc_arrays[name][key] = value
    end

    def self.assoc_keys(name)
      (@assoc_arrays[name] || {}).keys
    end

    def self.assoc_values(name)
      (@assoc_arrays[name] || {}).values
    end

    def self.assoc_length(name)
      (@assoc_arrays[name] || {}).length
    end

    def self.unset_assoc_array(name)
      @assoc_arrays.delete(name)
    end

    def self.unset_assoc_element(name, key)
      return unless @assoc_arrays[name]
      @assoc_arrays[name].delete(key)
    end

    # Coproc methods
    def self.coproc?(name)
      @coprocs.key?(name)
    end

    def self.get_coproc(name)
      @coprocs[name]
    end

    def self.set_coproc(name, pid:, read_fd:, write_fd:, reader:, writer:)
      @coprocs[name] = {
        pid: pid,
        read_fd: read_fd,
        write_fd: write_fd,
        reader: reader,
        writer: writer
      }
      # Store file descriptors as array (bash-compatible)
      set_array(name, [read_fd.to_s, write_fd.to_s])
      # Store PID as NAME_PID
      ENV["#{name}_PID"] = pid.to_s
    end

    def self.remove_coproc(name)
      coproc = @coprocs.delete(name)
      return unless coproc

      # Close file descriptors
      coproc[:reader]&.close rescue nil
      coproc[:writer]&.close rescue nil
      # Clean up array and PID env var
      unset_array(name)
      ENV.delete("#{name}_PID")
    end

    def self.coproc_read_fd(name)
      @coprocs.dig(name, :read_fd)
    end

    def self.coproc_write_fd(name)
      @coprocs.dig(name, :write_fd)
    end

    def self.coproc_pid(name)
      @coprocs.dig(name, :pid)
    end

    def self.coproc_reader(name)
      @coprocs.dig(name, :reader)
    end

    def self.coproc_writer(name)
      @coprocs.dig(name, :writer)
    end

    # Valid shell options with their default values and descriptions
    SHELL_OPTIONS = {
      'autocd' => [false, 'cd to a directory when typed as command'],
      'cdspell' => [false, 'correct minor spelling errors in cd'],
      'checkhash' => [false, 'check hash table before executing'],
      'checkjobs' => [false, 'check for running jobs before exit'],
      'cmdhist' => [true, 'save multi-line commands as single history entry'],
      'dotglob' => [false, 'include dotfiles in pathname expansion'],
      'expand_aliases' => [true, 'expand aliases'],
      'extglob' => [false, 'enable extended pattern matching'],
      'globstar' => [false, 'enable ** for recursive globbing'],
      'histappend' => [false, 'append to history file'],
      'histreedit' => [false, 'allow re-editing of failed history substitution'],
      'histverify' => [false, 'verify history substitution before executing'],
      'hostcomplete' => [true, 'attempt hostname completion'],
      'interactive_comments' => [true, 'allow comments in interactive shell'],
      'lithist' => [false, 'preserve newlines in multi-line history'],
      'login_shell' => [false, 'shell is a login shell (read-only)'],
      'nocaseglob' => [false, 'case-insensitive pathname expansion'],
      'nocasematch' => [false, 'case-insensitive pattern matching'],
      'nullglob' => [false, 'patterns matching nothing expand to null'],
      'progcomp' => [true, 'enable programmable completion'],
      'promptvars' => [true, 'expand variables in prompt strings'],
      'sourcepath' => [true, 'use PATH to find sourced files'],
      'xpg_echo' => [false, 'echo expands backslash-escape sequences']
    }.freeze

    def self.builtin?(name)
      COMMANDS.include?(name) && !@disabled_builtins.include?(name)
    end

    def self.builtin_exists?(name)
      COMMANDS.include?(name)
    end

    def self.builtin_enabled?(name)
      COMMANDS.include?(name) && !@disabled_builtins.include?(name)
    end

    def self.run(name, args)
      case name
      when 'cd'
        run_cd(args)
      when 'exit'
        run_exit(args)
      when 'logout'
        run_logout(args)
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
      when 'declare', 'typeset'
        run_declare(args)
      when 'let'
        run_let(args)
      when 'printf'
        run_printf(args)
      when 'type'
        run_type(args)
      when 'which'
        run_which(args)
      when 'true', ':'
        true
      when 'false'
        false
      when 'eval'
        run_eval(args)
      when 'command'
        run_command(args)
      when 'builtin'
        run_builtin(args)
      when 'wait'
        run_wait(args)
      when 'kill'
        run_kill(args)
      when 'umask'
        run_umask(args)
      when 'exec'
        run_exec(args)
      when 'times'
        run_times(args)
      when 'hash'
        run_hash(args)
      when 'disown'
        run_disown(args)
      when 'ulimit'
        run_ulimit(args)
      when 'suspend'
        run_suspend(args)
      when 'shopt'
        run_shopt(args)
      when 'enable'
        run_enable(args)
      when 'caller'
        run_caller(args)
      when 'complete'
        run_complete(args)
      when 'compgen'
        run_compgen(args)
      when 'compopt'
        run_compopt(args)
      when 'bind'
        run_bind(args)
      when 'help'
        run_help(args)
      when 'fc'
        run_fc(args)
      when 'mapfile', 'readarray'
        run_mapfile(args)
      else
        false
      end
    end

    def self.run_cd(args)
      # cd [-L|-P] [dir]
      # -L: follow symbolic links (default)
      # -P: use physical directory structure (don't follow symlinks)
      physical = set_option?('P')
      remaining_args = []

      args.each do |arg|
        case arg
        when '-P'
          physical = true
        when '-L'
          physical = false
        else
          remaining_args << arg
        end
      end

      dir = remaining_args.first || ENV['HOME']

      # Save OLDPWD before changing
      ENV['OLDPWD'] = ENV['PWD'] || Dir.pwd

      if physical
        # Resolve to physical path (no symlinks)
        target = File.realpath(File.expand_path(dir))
        Dir.chdir(target)
        ENV['PWD'] = target
      else
        Dir.chdir(dir)
        ENV['PWD'] = Dir.pwd
      end
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
      'ERR' => 'ERR',      # Pseudo-signal: triggered on command failure
      'DEBUG' => 'DEBUG',  # Pseudo-signal: triggered before each command
      'RETURN' => 'RETURN', # Pseudo-signal: triggered when function/sourced script returns
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

    # Pseudo-signals that are not real OS signals
    PSEUDO_SIGNALS = [0, 'ERR', 'DEBUG', 'RETURN'].freeze

    def self.set_trap(sig, command)
      # Store the trap command
      @traps[sig] = command

      # Pseudo-signals are handled by the shell, not the OS
      return if PSEUDO_SIGNALS.include?(sig)

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

      # Pseudo-signals have no OS signal to reset
      return if PSEUDO_SIGNALS.include?(sig)

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

    @in_err_trap = false

    def self.run_err_trap
      return unless @traps.key?('ERR')
      return if @in_err_trap  # Prevent recursion

      @in_err_trap = true
      begin
        @executor&.call(@traps['ERR']) if @executor
      ensure
        @in_err_trap = false
      end
    end

    def self.err_trap_set?
      @traps.key?('ERR') && !@traps['ERR'].empty?
    end

    def self.save_and_clear_err_trap
      # Save ERR trap and clear it (for functions/subshells when errtrace is off)
      saved = @traps.delete('ERR')
      saved
    end

    def self.restore_err_trap(saved)
      # Restore a previously saved ERR trap
      if saved
        @traps['ERR'] = saved
      end
    end

    @in_debug_trap = false

    def self.run_debug_trap
      return unless @traps.key?('DEBUG')
      return if @in_debug_trap  # Prevent recursion

      @in_debug_trap = true
      begin
        @executor&.call(@traps['DEBUG']) if @executor
      ensure
        @in_debug_trap = false
      end
    end

    def self.debug_trap_set?
      @traps.key?('DEBUG') && !@traps['DEBUG'].empty?
    end

    @in_return_trap = false

    def self.run_return_trap
      return unless @traps.key?('RETURN')
      return if @in_return_trap  # Prevent recursion

      @in_return_trap = true
      begin
        @executor&.call(@traps['RETURN']) if @executor
      ensure
        @in_return_trap = false
      end
    end

    def self.return_trap_set?
      @traps.key?('RETURN') && !@traps['RETURN'].empty?
    end

    def self.save_and_clear_functrace_traps
      # Save DEBUG and RETURN traps and clear them (for functions when functrace is off)
      saved = {}
      saved['DEBUG'] = @traps.delete('DEBUG') if @traps.key?('DEBUG')
      saved['RETURN'] = @traps.delete('RETURN') if @traps.key?('RETURN')
      saved.empty? ? nil : saved
    end

    def self.restore_functrace_traps(saved)
      # Restore previously saved DEBUG and RETURN traps
      return unless saved

      @traps['DEBUG'] = saved['DEBUG'] if saved['DEBUG']
      @traps['RETURN'] = saved['RETURN'] if saved['RETURN']
    end

    def self.clear_traps
      @traps.each_key do |sig|
        reset_trap(sig) unless PSEUDO_SIGNALS.include?(sig)
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

    def self.run_declare(args)
      # declare [-aAilrux] [-p] [name[=value] ...]
      # -a: indexed array
      # -A: associative array
      # -i: integer attribute (arithmetic evaluation)
      # -l: lowercase attribute
      # -u: uppercase attribute
      # -r: readonly attribute
      # -x: export attribute
      # -p: print declarations
      # +attr: remove attribute

      # Parse options
      print_mode = false
      array_mode = nil  # :indexed or :associative
      add_attrs = Set.new
      remove_attrs = Set.new
      names = []

      args.each do |arg|
        if arg.start_with?('-')
          if arg == '-p'
            print_mode = true
          else
            # Parse attribute flags
            arg[1..].each_char do |c|
              case c
              when 'a' then array_mode = :indexed
              when 'A' then array_mode = :associative
              when 'i' then add_attrs << :integer
              when 'l' then add_attrs << :lowercase
              when 'u' then add_attrs << :uppercase
              when 'r' then add_attrs << :readonly
              when 'x' then add_attrs << :export
              when 'p' then print_mode = true
              end
            end
          end
        elsif arg.start_with?('+')
          # Remove attributes
          arg[1..].each_char do |c|
            case c
            when 'i' then remove_attrs << :integer
            when 'l' then remove_attrs << :lowercase
            when 'u' then remove_attrs << :uppercase
            when 'x' then remove_attrs << :export
            # Note: can't remove readonly
            end
          end
        else
          names << arg
        end
      end

      # Handle array declarations
      if array_mode && !print_mode
        names.each do |name|
          var_name = name.split('=').first
          if array_mode == :associative
            declare_assoc_array(var_name)
          else
            set_array(var_name, []) unless array?(var_name)
          end
        end
        return true if add_attrs.empty? && remove_attrs.empty?
      end

      # Print mode with no names: show all declared variables
      if print_mode && names.empty?
        print_all_declarations(add_attrs)
        return true
      end

      # Print mode with names: show specific declarations
      if print_mode && names.any?
        names.each do |name|
          var_name = name.split('=', 2).first
          print_declaration(var_name)
        end
        return true
      end

      # No names and no attrs: list all
      if names.empty? && add_attrs.empty? && remove_attrs.empty?
        print_all_declarations(Set.new)
        return true
      end

      # Process each name
      names.each do |arg|
        if arg.include?('=')
          name, value = arg.split('=', 2)
        else
          name = arg
          value = nil
        end

        # Check readonly
        if readonly?(name) && value
          puts "declare: #{name}: readonly variable"
          next
        end

        # Initialize attributes set for this variable
        @var_attributes[name] ||= Set.new

        # Add new attributes
        add_attrs.each { |attr| @var_attributes[name] << attr }

        # Remove attributes (except readonly)
        remove_attrs.each { |attr| @var_attributes[name].delete(attr) }

        # Handle readonly attribute
        if add_attrs.include?(:readonly)
          @readonly_vars[name] = true
        end

        # Handle export attribute
        if add_attrs.include?(:export)
          # Variable is marked for export (already in ENV)
        end

        # Set value if provided
        if value
          value = apply_attributes(name, value)
          ENV[name] = value
        end
      end

      true
    end

    def self.apply_attributes(name, value)
      attrs = @var_attributes[name] || Set.new

      # Apply integer attribute
      if attrs.include?(:integer)
        # Evaluate as arithmetic expression
        begin
          # Simple arithmetic evaluation
          result = eval(value.gsub(/[a-zA-Z_][a-zA-Z0-9_]*/) { |var| ENV[var] || '0' })
          value = result.to_s
        rescue StandardError
          value = '0'
        end
      end

      # Apply case attributes (lowercase takes precedence if both set)
      if attrs.include?(:lowercase)
        value = value.downcase
      elsif attrs.include?(:uppercase)
        value = value.upcase
      end

      value
    end

    def self.set_var_with_attributes(name, value)
      # Apply attributes when setting a variable
      if @var_attributes[name]
        value = apply_attributes(name, value)
      end
      ENV[name] = value
    end

    def self.print_declaration(name)
      attrs = @var_attributes[name] || Set.new
      flags = +''
      flags << 'i' if attrs.include?(:integer)
      flags << 'l' if attrs.include?(:lowercase)
      flags << 'u' if attrs.include?(:uppercase)
      flags << 'r' if readonly?(name)
      flags << 'x' if attrs.include?(:export)

      value = ENV[name]
      if flags.empty?
        if value
          puts "declare -- #{name}=#{value.inspect}"
        else
          puts "declare -- #{name}"
        end
      else
        if value
          puts "declare -#{flags} #{name}=#{value.inspect}"
        else
          puts "declare -#{flags} #{name}"
        end
      end
    end

    def self.print_all_declarations(filter_attrs)
      # Collect all variables with attributes
      vars_to_print = Set.new

      @var_attributes.each_key { |name| vars_to_print << name }
      @readonly_vars.each_key { |name| vars_to_print << name }

      vars_to_print.each do |name|
        attrs = @var_attributes[name] || Set.new
        attrs = attrs.dup
        attrs << :readonly if readonly?(name)

        # Filter by attributes if specified
        if filter_attrs.empty? || filter_attrs.subset?(attrs)
          print_declaration(name)
        end
      end
    end

    def self.get_var_attributes(name)
      @var_attributes[name] || Set.new
    end

    def self.has_attribute?(name, attr)
      (@var_attributes[name] || Set.new).include?(attr)
    end

    def self.mark_exported(name)
      @var_attributes[name] ||= Set.new
      @var_attributes[name] << :export
    end

    def self.clear_var_attributes
      @var_attributes.clear
    end

    def self.run_let(args)
      # let expression [expression ...]
      # Evaluates arithmetic expressions
      # Returns 0 (true) if last expression is non-zero, 1 (false) if zero

      if args.empty?
        puts 'let: usage: let expression [expression ...]'
        return false
      end

      last_result = 0

      args.each do |expr|
        last_result = evaluate_arithmetic(expr)
      end

      # Return true if last result is non-zero (shell convention)
      last_result != 0
    end

    def self.evaluate_arithmetic(expr)
      # Handle assignment operators (but not ==, !=, <=, >=)
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\s*([\+\-\*\/%]?=)(?!=)\s*(.+)\z/
        var_name = $1
        operator = $2
        value_expr = $3

        # Check readonly
        if readonly?(var_name)
          puts "let: #{var_name}: readonly variable"
          return 0
        end

        # Evaluate the right side
        value = evaluate_arithmetic_expr(value_expr)

        if operator == '='
          # Simple assignment
          ENV[var_name] = value.to_s
        else
          # Compound assignment (+=, -=, *=, /=, %=)
          current = (ENV[var_name] || '0').to_i
          case operator
          when '+='
            ENV[var_name] = (current + value).to_s
          when '-='
            ENV[var_name] = (current - value).to_s
          when '*='
            ENV[var_name] = (current * value).to_s
          when '/='
            ENV[var_name] = (value.zero? ? 0 : current / value).to_s
          when '%='
            ENV[var_name] = (value.zero? ? 0 : current % value).to_s
          end
        end

        return ENV[var_name].to_i
      end

      # Handle increment/decrement operators
      if expr =~ /\A\+\+([a-zA-Z_][a-zA-Z0-9_]*)\z/
        # Pre-increment
        var_name = $1
        return 0 if readonly?(var_name)
        val = (ENV[var_name] || '0').to_i + 1
        ENV[var_name] = val.to_s
        return val
      end

      if expr =~ /\A--([a-zA-Z_][a-zA-Z0-9_]*)\z/
        # Pre-decrement
        var_name = $1
        return 0 if readonly?(var_name)
        val = (ENV[var_name] || '0').to_i - 1
        ENV[var_name] = val.to_s
        return val
      end

      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\+\+\z/
        # Post-increment
        var_name = $1
        return 0 if readonly?(var_name)
        old_val = (ENV[var_name] || '0').to_i
        ENV[var_name] = (old_val + 1).to_s
        return old_val
      end

      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)--\z/
        # Post-decrement
        var_name = $1
        return 0 if readonly?(var_name)
        old_val = (ENV[var_name] || '0').to_i
        ENV[var_name] = (old_val - 1).to_s
        return old_val
      end

      # Just evaluate the expression
      evaluate_arithmetic_expr(expr)
    end

    def self.evaluate_arithmetic_expr(expr)
      # Replace variable references with their values
      # Handle $VAR, ${VAR}, and bare variable names
      expanded = expr.gsub(/\$\{([^}]+)\}|\$([a-zA-Z_][a-zA-Z0-9_]*)|([a-zA-Z_][a-zA-Z0-9_]*)/) do |match|
        if $1
          # ${VAR} form
          (ENV[$1] || '0')
        elsif $2
          # $VAR form
          (ENV[$2] || '0')
        elsif $3
          # Plain variable name - in arithmetic context, unset vars default to 0
          (ENV[$3] || '0')
        else
          match
        end
      end

      # Handle comparison operators (convert to Ruby equivalents)
      expanded = expanded.gsub('==', '==')
      expanded = expanded.gsub('!=', '!=')
      expanded = expanded.gsub('<=', '<=')
      expanded = expanded.gsub('>=', '>=')

      # Handle logical operators
      expanded = expanded.gsub('&&', ' && ')
      expanded = expanded.gsub('||', ' || ')
      expanded = expanded.gsub(/!(?!=)/, ' !')

      # Handle ternary operator
      expanded = expanded.gsub('?', ' ? ').gsub(':', ' : ')

      # Evaluate safely
      begin
        result = eval(expanded)
        result.is_a?(Integer) ? result : (result ? 1 : 0)
      rescue StandardError
        0
      end
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
            # Apply attributes if any
            value = apply_attributes(key, value)
            ENV[key] = value
            # Mark as exported
            @var_attributes[key] ||= Set.new
            @var_attributes[key] << :export
          else
            # Just export existing variable
            @var_attributes[arg] ||= Set.new
            @var_attributes[arg] << :export
            puts "export: #{arg}=#{ENV[arg]}" if ENV.key?(arg)
          end
        end
      end
      true
    end

    def self.run_pwd(args)
      # pwd [-L|-P]
      # -L: print logical path (may contain symlinks, default)
      # -P: print physical path (no symlinks)
      physical = set_option?('P')

      args.each do |arg|
        case arg
        when '-P'
          physical = true
        when '-L'
          physical = false
        end
      end

      if physical
        puts File.realpath(Dir.pwd)
      else
        # Use PWD if set and valid, otherwise Dir.pwd
        pwd = ENV['PWD']
        if pwd && File.directory?(pwd)
          puts pwd
        else
          puts Dir.pwd
        end
      end
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

    # Shell option flags (set -o options)
    @set_options = {
      'B' => true,   # braceexpand: enable brace expansion (enabled by default)
      'H' => true,   # histexpand: enable ! style history expansion (enabled by default)
      'e' => false,  # errexit: exit on error
      'E' => false,  # errtrace: ERR trap inherited by functions/subshells
      'T' => false,  # functrace: DEBUG/RETURN traps inherited by functions/subshells
      'x' => false,  # xtrace: print commands
      'u' => false,  # nounset: error on unset variables
      'n' => false,  # noexec: don't execute (syntax check)
      'v' => false,  # verbose: print input lines
      'f' => false,  # noglob: disable globbing
      'C' => false,  # noclobber: don't overwrite files with >
      'a' => false,  # allexport: export all variables
      'b' => false,  # notify: report job status immediately
      'h' => false,  # hashall: hash commands
      'm' => false,  # monitor: job control
      'pipefail' => false,  # pipefail: pipeline fails if any command fails
      'globstar' => false,  # globstar: ** matches directories recursively
      'nullglob' => false,  # nullglob: patterns matching nothing expand to nothing
      'failglob' => false,  # failglob: patterns matching nothing cause an error
      'dotglob' => false,   # dotglob: globs match files starting with .
      'nocaseglob' => false, # nocaseglob: case-insensitive globbing
      'ignoreeof' => false,  # ignoreeof: don't exit on EOF (Ctrl+D)
      'extglob' => false,    # extglob: extended pattern matching operators
      'P' => false,          # physical: don't follow symlinks for cd/pwd
      'emacs' => true,       # emacs: use emacs-style line editing (default)
      'vi' => false,         # vi: use vi-style line editing
      'nocasematch' => false, # nocasematch: case-insensitive pattern matching in case/[[
      't' => false,          # onecmd: exit after reading and executing one command
      'k' => false,          # keyword: all assignment args placed in environment
      'p' => false,          # privileged: don't read startup files, ignore some env vars
    }

    def self.set_options
      @set_options
    end

    def self.set_option?(flag)
      @set_options[flag] || false
    end

    def self.run_set(args)
      # set [-+abCefhmnuvx] [-o option] [--] [arg...]
      # With no args, clear positional params (original behavior)
      if args.empty?
        @positional_params_setter&.call([])
        return true
      end

      i = 0
      while i < args.length
        arg = args[i]

        if arg == '--'
          # Everything after -- is positional params
          @positional_params_setter&.call(args[i + 1..] || [])
          return true
        elsif arg == '-o'
          # Long option form: set -o errexit, or just set -o to list
          i += 1
          opt_name = args[i]
          if opt_name
            set_long_option(opt_name, true)
          else
            # set -o with no option name lists all options
            list_set_options
            return true
          end
        elsif arg == '+o'
          # Disable long option: set +o errexit, or list with set +o
          i += 1
          opt_name = args[i]
          if opt_name
            set_long_option(opt_name, false)
          else
            list_set_options
            return true
          end
        elsif arg.start_with?('-') && arg.length > 1 && arg != '-'
          # Short options: -e, -x, -ex
          arg[1..].each_char { |c| @set_options[c] = true if @set_options.key?(c) }
        elsif arg.start_with?('+') && arg.length > 1
          # Disable short options: +e, +x
          arg[1..].each_char { |c| @set_options[c] = false if @set_options.key?(c) }
        else
          # Positional parameters
          @positional_params_setter&.call(args[i..])
          return true
        end
        i += 1
      end
      true
    end

    def self.list_set_options
      # Print current option settings
      long_names = {
        'B' => 'braceexpand', 'H' => 'histexpand',
        'e' => 'errexit', 'E' => 'errtrace', 'T' => 'functrace',
        'x' => 'xtrace', 'u' => 'nounset', 'n' => 'noexec', 'v' => 'verbose',
        'f' => 'noglob', 'C' => 'noclobber', 'a' => 'allexport', 'b' => 'notify',
        'h' => 'hashall', 'm' => 'monitor', 'pipefail' => 'pipefail',
        'globstar' => 'globstar', 'nullglob' => 'nullglob', 'failglob' => 'failglob',
        'dotglob' => 'dotglob', 'nocaseglob' => 'nocaseglob', 'ignoreeof' => 'ignoreeof',
        'extglob' => 'extglob', 'P' => 'physical', 'emacs' => 'emacs', 'vi' => 'vi',
        'nocasematch' => 'nocasematch', 't' => 'onecmd', 'k' => 'keyword',
        'p' => 'privileged'
      }
      @set_options.each do |flag, value|
        name = long_names[flag] || flag
        state = value ? '-o' : '+o'
        puts "set #{state} #{name}"
      end
      true
    end

    def self.set_long_option(name, value)
      mapping = {
        'braceexpand' => 'B', 'histexpand' => 'H',
        'errexit' => 'e', 'errtrace' => 'E', 'functrace' => 'T',
        'xtrace' => 'x', 'nounset' => 'u', 'noexec' => 'n', 'verbose' => 'v',
        'noglob' => 'f', 'noclobber' => 'C', 'allexport' => 'a', 'notify' => 'b',
        'hashall' => 'h', 'monitor' => 'm', 'pipefail' => 'pipefail',
        'globstar' => 'globstar', 'nullglob' => 'nullglob', 'failglob' => 'failglob',
        'dotglob' => 'dotglob', 'nocaseglob' => 'nocaseglob', 'ignoreeof' => 'ignoreeof',
        'extglob' => 'extglob', 'physical' => 'P', 'emacs' => 'emacs', 'vi' => 'vi',
        'nocasematch' => 'nocasematch', 'onecmd' => 't', 'keyword' => 'k',
        'privileged' => 'p'
      }
      flag = mapping[name]
      return unless flag

      # vi and emacs are mutually exclusive
      if flag == 'vi' && value
        @set_options['vi'] = true
        @set_options['emacs'] = false
        Reline.vi_editing_mode if defined?(Reline)
      elsif flag == 'emacs' && value
        @set_options['emacs'] = true
        @set_options['vi'] = false
        Reline.emacs_editing_mode if defined?(Reline)
      elsif flag == 'vi' && !value
        # Disabling vi enables emacs
        @set_options['vi'] = false
        @set_options['emacs'] = true
        Reline.emacs_editing_mode if defined?(Reline)
      elsif flag == 'emacs' && !value
        # Disabling emacs enables vi
        @set_options['emacs'] = false
        @set_options['vi'] = true
        Reline.vi_editing_mode if defined?(Reline)
      else
        @set_options[flag] = value
      end
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

    def self.run_printf(args)
      # printf format [arguments...]
      # Supports: %s, %d, %i, %f, %e, %g, %x, %X, %o, %c, %b, %%
      # Also supports width, precision, and flags: %-10s, %05d, %.2f, etc.

      if args.empty?
        puts 'printf: usage: printf format [arguments]'
        return false
      end

      format = args.first
      arguments = args[1..] || []
      arg_index = 0

      # Process escape sequences in format string
      format = process_escape_sequences(format)

      # Build output by processing format specifiers
      output = +''
      i = 0
      while i < format.length
        if format[i] == '%'
          if i + 1 < format.length && format[i + 1] == '%'
            # Literal %
            output << '%'
            i += 2
            next
          end

          # Parse format specifier
          spec_start = i
          i += 1

          # Parse flags
          flags = +''
          while i < format.length && '-+ #0'.include?(format[i])
            flags << format[i]
            i += 1
          end

          # Parse width
          width = +''
          while i < format.length && format[i] =~ /\d/
            width << format[i]
            i += 1
          end

          # Parse precision
          precision = nil
          if i < format.length && format[i] == '.'
            i += 1
            precision = +''
            while i < format.length && format[i] =~ /\d/
              precision << format[i]
              i += 1
            end
          end

          # Parse conversion specifier
          if i < format.length
            specifier = format[i]
            i += 1

            # Get argument (reuse arguments if we run out)
            arg = if arg_index < arguments.length
                    arguments[arg_index]
                  else
                    specifier =~ /[diouxXeEfFgG]/ ? '0' : ''
                  end
            arg_index += 1

            # Format the argument
            output << format_arg(specifier, arg, flags, width, precision)
          end
        else
          output << format[i]
          i += 1
        end
      end

      print output
      true
    end

    def self.process_escape_sequences(str)
      str.gsub(/\\(.)/) do |match|
        case $1
        when 'n' then "\n"
        when 't' then "\t"
        when 'r' then "\r"
        when 'a' then "\a"
        when 'b' then "\b"
        when 'f' then "\f"
        when 'v' then "\v"
        when '\\' then '\\'
        when "'" then "'"
        when '"' then '"'
        when '0'
          # Octal escape - simplified handling
          '\0'
        else
          match
        end
      end
    end

    def self.format_arg(specifier, arg, flags, width, precision)
      width_int = width.empty? ? nil : width.to_i
      prec_int = precision.nil? ? nil : (precision.empty? ? 0 : precision.to_i)

      result = case specifier
               when 's'
                 # String
                 s = arg.to_s
                 s = s[0, prec_int] if prec_int
                 s
               when 'd', 'i'
                 # Signed integer
                 num = arg.to_i
                 if prec_int
                   format("%0#{prec_int}d", num)
                 else
                   num.to_s
                 end
               when 'u'
                 # Unsigned integer
                 num = arg.to_i
                 num = num & 0xFFFFFFFF if num < 0
                 num.to_s
               when 'o'
                 # Octal
                 num = arg.to_i
                 prefix = flags.include?('#') ? '0' : ''
                 "#{prefix}#{num.to_s(8)}"
               when 'x'
                 # Hexadecimal lowercase
                 num = arg.to_i
                 prefix = flags.include?('#') ? '0x' : ''
                 "#{prefix}#{num.to_s(16)}"
               when 'X'
                 # Hexadecimal uppercase
                 num = arg.to_i
                 prefix = flags.include?('#') ? '0X' : ''
                 "#{prefix}#{num.to_s(16).upcase}"
               when 'f', 'F'
                 # Floating point
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}f", num)
               when 'e'
                 # Scientific notation lowercase
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}e", num)
               when 'E'
                 # Scientific notation uppercase
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}E", num)
               when 'g'
                 # Shorter of %e or %f
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}g", num)
               when 'G'
                 # Shorter of %E or %F
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}G", num)
               when 'c'
                 # Character
                 arg.to_s[0] || ''
               when 'b'
                 # String with backslash escapes
                 process_escape_sequences(arg.to_s)
               else
                 arg.to_s
               end

      # Apply width and alignment
      if width_int
        if flags.include?('-')
          # Left-justify
          result = result.ljust(width_int)
        elsif flags.include?('0') && specifier =~ /[diouxXeEfFgG]/
          # Zero-pad numbers
          if result[0] == '-'
            result = "-#{result[1..].rjust(width_int - 1, '0')}"
          else
            result = result.rjust(width_int, '0')
          end
        else
          # Right-justify with spaces
          result = result.rjust(width_int)
        end
      end

      # Handle + flag for numbers
      if flags.include?('+') && specifier =~ /[dieEfFgG]/ && !result.start_with?('-')
        result = "+#{result}"
      elsif flags.include?(' ') && specifier =~ /[dieEfFgG]/ && !result.start_with?('-')
        result = " #{result}"
      end

      result
    end

    def self.run_type(args)
      # type [-afptP] name [name ...]
      # -a: display all locations containing an executable named name
      # -f: suppress function lookup
      # -p: return path only for external commands
      # -t: output single word: alias, keyword, function, builtin, file, or nothing
      # -P: force PATH search even if name is alias, function, or builtin

      if args.empty?
        puts 'type: usage: type [-afptP] name [name ...]'
        return false
      end

      # Parse options
      show_all = false
      suppress_functions = false
      path_only = false
      type_only = false
      force_path = false
      names = []

      args.each do |arg|
        if arg.start_with?('-') && arg.length > 1
          arg[1..].each_char do |c|
            case c
            when 'a' then show_all = true
            when 'f' then suppress_functions = true
            when 'p' then path_only = true
            when 't' then type_only = true
            when 'P' then force_path = true
            end
          end
        else
          names << arg
        end
      end

      if names.empty?
        puts 'type: usage: type [-afptP] name [name ...]'
        return false
      end

      all_found = true

      names.each do |name|
        found = false

        # Check alias (unless force_path)
        unless force_path
          if @aliases.key?(name)
            found = true
            if type_only
              puts 'alias'
            elsif !path_only
              puts "#{name} is aliased to '#{@aliases[name]}'"
            end
            next unless show_all
          end
        end

        # Check function (unless force_path or suppress_functions)
        unless force_path || suppress_functions
          if @function_checker&.call(name)
            found = true
            if type_only
              puts 'function'
            elsif !path_only
              puts "#{name} is a function"
            end
            next unless show_all
          end
        end

        # Check builtin (unless force_path)
        unless force_path
          if builtin?(name)
            found = true
            if type_only
              puts 'builtin'
            elsif !path_only
              puts "#{name} is a shell builtin"
            end
            next unless show_all
          end
        end

        # Check PATH for external command
        path = find_in_path(name)
        if path
          found = true
          if type_only
            puts 'file'
          elsif path_only || force_path
            puts path
          else
            puts "#{name} is #{path}"
          end
        end

        unless found
          puts "type: #{name}: not found" unless type_only
          all_found = false
        end
      end

      all_found
    end

    def self.find_in_path(name)
      # If name contains a slash, check if it's executable
      if name.include?('/')
        return name if File.executable?(name)
        return nil
      end

      # Search PATH
      path_dirs = (ENV['PATH'] || '').split(File::PATH_SEPARATOR)
      path_dirs.each do |dir|
        full_path = File.join(dir, name)
        return full_path if File.executable?(full_path) && !File.directory?(full_path)
      end

      nil
    end

    def self.find_all_in_path(name)
      # Find all matching executables in PATH
      results = []

      # If name contains a slash, just check if it's executable
      if name.include?('/')
        results << name if File.executable?(name)
        return results
      end

      # Search PATH
      path_dirs = (ENV['PATH'] || '').split(File::PATH_SEPARATOR)
      path_dirs.each do |dir|
        full_path = File.join(dir, name)
        if File.executable?(full_path) && !File.directory?(full_path)
          results << full_path
        end
      end

      results
    end

    def self.run_disown(args)
      # disown [-h] [-ar] [jobspec ...]
      # -h: mark jobs so SIGHUP is not sent (but keep in table)
      # -a: remove all jobs
      # -r: remove only running jobs
      # Without args: removes current job

      mark_nohup = false
      all_jobs = false
      running_only = false
      job_specs = []

      args.each do |arg|
        if arg.start_with?('-') && job_specs.empty?
          arg[1..].each_char do |c|
            case c
            when 'h' then mark_nohup = true
            when 'a' then all_jobs = true
            when 'r' then running_only = true
            else
              puts "disown: -#{c}: invalid option"
              return false
            end
          end
        else
          job_specs << arg
        end
      end

      manager = JobManager.instance

      if all_jobs
        # Remove/mark all jobs
        jobs = manager.all
        jobs = jobs.select(&:running?) if running_only
        jobs.each do |job|
          if mark_nohup
            job.status = :nohup
          else
            manager.remove(job.id)
          end
        end
        return true
      end

      if job_specs.empty?
        # Remove current job
        job = manager.last
        unless job
          puts 'disown: current: no such job'
          return false
        end
        if mark_nohup
          job.status = :nohup
        else
          manager.remove(job.id)
        end
        return true
      end

      # Remove specified jobs
      all_found = true
      job_specs.each do |spec|
        job = nil

        if spec.start_with?('%')
          job_id = spec[1..].to_i
          job = manager.get(job_id)
        else
          # Try as PID
          pid = spec.to_i
          job = manager.find_by_pid(pid)
        end

        unless job
          puts "disown: #{spec}: no such job"
          all_found = false
          next
        end

        if running_only && !job.running?
          next
        end

        if mark_nohup
          job.status = :nohup
        else
          manager.remove(job.id)
        end
      end

      all_found
    end

    def self.run_ulimit(args)
      # ulimit [-HSabcdefiklmnpqrstuvxPRT] [limit]
      # -H: use hard limit
      # -S: use soft limit (default for display)
      # -a: show all limits
      # Resource flags:
      # -c: core file size (blocks)
      # -d: data segment size (kbytes)
      # -e: scheduling priority (nice)
      # -f: file size (blocks) - default
      # -i: pending signals
      # -l: locked memory (kbytes)
      # -m: resident set size (kbytes)
      # -n: open files
      # -p: pipe size (512 bytes)
      # -q: POSIX message queues (bytes)
      # -r: real-time priority
      # -s: stack size (kbytes)
      # -t: CPU time (seconds)
      # -u: user processes
      # -v: virtual memory (kbytes)
      # -x: file locks

      # Resource mapping to Ruby Process constants
      resource_map = {
        'c' => [:RLIMIT_CORE, 512, 'core file size'],           # blocks
        'd' => [:RLIMIT_DATA, 1024, 'data seg size'],           # kbytes
        'f' => [:RLIMIT_FSIZE, 512, 'file size'],               # blocks
        'l' => [:RLIMIT_MEMLOCK, 1024, 'max locked memory'],    # kbytes
        'm' => [:RLIMIT_RSS, 1024, 'max memory size'],          # kbytes
        'n' => [:RLIMIT_NOFILE, 1, 'open files'],               # count
        's' => [:RLIMIT_STACK, 1024, 'stack size'],             # kbytes
        't' => [:RLIMIT_CPU, 1, 'cpu time'],                    # seconds
        'u' => [:RLIMIT_NPROC, 1, 'max user processes'],        # count
        'v' => [:RLIMIT_AS, 1024, 'virtual memory']             # kbytes
      }

      # Add platform-specific resources if available
      resource_map['i'] = [:RLIMIT_SIGPENDING, 1, 'pending signals'] if Process.const_defined?(:RLIMIT_SIGPENDING)
      resource_map['q'] = [:RLIMIT_MSGQUEUE, 1, 'POSIX message queues'] if Process.const_defined?(:RLIMIT_MSGQUEUE)
      resource_map['e'] = [:RLIMIT_NICE, 1, 'scheduling priority'] if Process.const_defined?(:RLIMIT_NICE)
      resource_map['r'] = [:RLIMIT_RTPRIO, 1, 'real-time priority'] if Process.const_defined?(:RLIMIT_RTPRIO)
      resource_map['x'] = [:RLIMIT_LOCKS, 1, 'file locks'] if Process.const_defined?(:RLIMIT_LOCKS)

      use_hard = false
      use_soft = true  # default
      show_all = false
      resource_flag = 'f'  # default is file size
      limit_value = nil

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-') && limit_value.nil?
          arg[1..].each_char do |c|
            case c
            when 'H'
              use_hard = true
              use_soft = false
            when 'S'
              use_soft = true
              use_hard = false
            when 'a'
              show_all = true
            when *resource_map.keys
              resource_flag = c
            else
              puts "ulimit: -#{c}: invalid option"
              return false
            end
          end
        else
          limit_value = arg
        end
        i += 1
      end

      # Show all limits
      if show_all
        resource_map.each do |flag, (const_sym, divisor, description)|
          next unless Process.const_defined?(const_sym)

          const = Process.const_get(const_sym)
          begin
            soft, hard = Process.getrlimit(const)
            value = use_hard ? hard : soft
            if value == Process::RLIM_INFINITY
              formatted = 'unlimited'
            else
              formatted = (value / divisor).to_s
            end
            unit = case flag
                   when 't' then '(seconds, -t)'
                   when 'n', 'u' then "(-#{flag})"
                   else "(kbytes, -#{flag})"
                   end
            # Left-align description, right-align value
            puts format('%-30s %s', "#{description} #{unit}", formatted)
          rescue Errno::EINVAL
            # Resource not supported on this platform
          end
        end
        return true
      end

      # Get resource info
      resource_info = resource_map[resource_flag]
      unless resource_info
        puts "ulimit: -#{resource_flag}: invalid option"
        return false
      end

      const_sym, divisor, _description = resource_info

      unless Process.const_defined?(const_sym)
        puts "ulimit: -#{resource_flag}: not supported on this platform"
        return false
      end

      const = Process.const_get(const_sym)

      # Display current limit
      if limit_value.nil?
        begin
          soft, hard = Process.getrlimit(const)
          value = use_hard ? hard : soft
          if value == Process::RLIM_INFINITY
            puts 'unlimited'
          else
            puts (value / divisor).to_s
          end
          return true
        rescue Errno::EINVAL
          puts "ulimit: -#{resource_flag}: cannot get limit"
          return false
        end
      end

      # Set new limit
      new_limit = if limit_value == 'unlimited' || limit_value == 'infinity'
                    Process::RLIM_INFINITY
                  elsif limit_value == 'hard'
                    _, hard = Process.getrlimit(const)
                    hard
                  elsif limit_value == 'soft'
                    soft, _ = Process.getrlimit(const)
                    soft
                  elsif limit_value =~ /^\d+$/
                    limit_value.to_i * divisor
                  else
                    puts "ulimit: #{limit_value}: invalid limit"
                    return false
                  end

      begin
        soft, hard = Process.getrlimit(const)
        if use_hard && use_soft
          Process.setrlimit(const, new_limit, new_limit)
        elsif use_hard
          Process.setrlimit(const, soft, new_limit)
        else
          Process.setrlimit(const, new_limit, hard)
        end
        true
      rescue Errno::EPERM
        puts "ulimit: -#{resource_flag}: cannot modify limit"
        false
      rescue Errno::EINVAL
        puts "ulimit: -#{resource_flag}: invalid limit"
        false
      end
    end

    def self.run_suspend(args)
      # suspend [-f]
      # Suspend shell execution
      # -f: force suspend even if login shell

      force = false

      args.each do |arg|
        if arg == '-f'
          force = true
        elsif arg.start_with?('-')
          puts "suspend: #{arg}: invalid option"
          return false
        end
      end

      # Check if this is a login shell (unless -f is specified)
      unless force
        # A login shell typically has $0 starting with '-' or SHLVL=1
        if ENV['SHLVL'] == '1'
          puts 'suspend: cannot suspend a login shell'
          return false
        end
      end

      # Send SIGSTOP to ourselves
      begin
        Process.kill('STOP', Process.pid)
        true
      rescue Errno::EPERM
        puts 'suspend: cannot suspend'
        false
      end
    end

    def self.run_shopt(args)
      # shopt [-pqsu] [-o] [optname ...]
      # -s: enable (set) options
      # -u: disable (unset) options
      # -p: print in reusable format
      # -q: quiet mode, return status only
      # -o: restrict to set -o options (not implemented)

      set_mode = false
      unset_mode = false
      print_mode = false
      quiet_mode = false
      opt_names = []

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-') && opt_names.empty?
          arg[1..].each_char do |c|
            case c
            when 's'
              set_mode = true
            when 'u'
              unset_mode = true
            when 'p'
              print_mode = true
            when 'q'
              quiet_mode = true
            when 'o'
              # -o is for set -o options, we'll just ignore it
              nil
            else
              puts "shopt: -#{c}: invalid option"
              return false
            end
          end
        else
          opt_names << arg
        end
        i += 1
      end

      # Can't use both -s and -u
      if set_mode && unset_mode
        puts 'shopt: cannot set and unset options simultaneously'
        return false
      end

      # Helper to get current value of an option
      get_option = lambda do |name|
        if @shell_options.key?(name)
          @shell_options[name]
        elsif SHELL_OPTIONS.key?(name)
          SHELL_OPTIONS[name][0]  # default value
        else
          nil
        end
      end

      # Helper to print an option
      print_option = lambda do |name, value|
        unless quiet_mode
          if print_mode
            puts "shopt #{value ? '-s' : '-u'} #{name}"
          else
            puts "#{name}\t\t#{value ? 'on' : 'off'}"
          end
        end
      end

      # No options specified: list all or specified options
      unless set_mode || unset_mode
        if opt_names.empty?
          # List all options
          SHELL_OPTIONS.each_key do |name|
            value = get_option.call(name)
            print_option.call(name, value)
          end
          return true
        else
          # List specified options
          all_on = true
          opt_names.each do |name|
            unless SHELL_OPTIONS.key?(name)
              puts "shopt: #{name}: invalid shell option name" unless quiet_mode
              return false
            end
            value = get_option.call(name)
            print_option.call(name, value)
            all_on = false unless value
          end
          return all_on  # Return status indicates if all are on
        end
      end

      # Set or unset options
      if opt_names.empty?
        # List options that are on (with -s) or off (with -u)
        SHELL_OPTIONS.each_key do |name|
          value = get_option.call(name)
          if (set_mode && value) || (unset_mode && !value)
            print_option.call(name, value)
          end
        end
        return true
      end

      # Set or unset specified options
      opt_names.each do |name|
        unless SHELL_OPTIONS.key?(name)
          puts "shopt: #{name}: invalid shell option name"
          return false
        end

        # Check for read-only options
        if name == 'login_shell'
          puts "shopt: #{name}: cannot set option"
          return false
        end

        @shell_options[name] = set_mode
      end

      true
    end

    def self.shopt_enabled?(name)
      if @shell_options.key?(name)
        @shell_options[name]
      elsif SHELL_OPTIONS.key?(name)
        SHELL_OPTIONS[name][0]
      else
        false
      end
    end

    def self.run_enable(args)
      # enable [-a] [-dnps] [-f filename] [name ...]
      # -a: list all builtins (enabled and disabled)
      # -n: disable builtins
      # -p: print in reusable format
      # -s: list only POSIX special builtins
      # -d: remove a builtin loaded with -f (not implemented)
      # -f: load builtin from shared object (not implemented)

      show_all = false
      disable_mode = false
      print_mode = false
      special_only = false
      names = []

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-') && names.empty?
          arg[1..].each_char do |c|
            case c
            when 'a'
              show_all = true
            when 'n'
              disable_mode = true
            when 'p'
              print_mode = true
            when 's'
              special_only = true
            when 'd', 'f'
              # -d and -f are for dynamic loading, not implemented
              puts "enable: -#{c}: not supported"
              return false
            else
              puts "enable: -#{c}: invalid option"
              return false
            end
          end
        else
          names << arg
        end
        i += 1
      end

      # POSIX special builtins
      special_builtins = %w[. : break continue eval exec exit export readonly return set shift trap unset].freeze

      # Helper to print a builtin
      print_builtin = lambda do |name, enabled|
        if print_mode
          puts "enable #{enabled ? '' : '-n '}#{name}"
        else
          puts "enable #{enabled ? '' : '-n '}#{name}"
        end
      end

      # No names specified: list builtins
      if names.empty?
        builtins_to_show = special_only ? special_builtins : COMMANDS

        builtins_to_show.each do |name|
          next unless COMMANDS.include?(name)

          enabled = !@disabled_builtins.include?(name)

          if show_all
            print_builtin.call(name, enabled)
          elsif disable_mode
            # -n without names: show disabled builtins
            print_builtin.call(name, enabled) unless enabled
          else
            # No flags: show enabled builtins
            print_builtin.call(name, enabled) if enabled
          end
        end
        return true
      end

      # Enable or disable specified builtins
      names.each do |name|
        unless COMMANDS.include?(name)
          puts "enable: #{name}: not a shell builtin"
          return false
        end

        if disable_mode
          @disabled_builtins.add(name)
        else
          @disabled_builtins.delete(name)
        end
      end

      true
    end

    def self.run_caller(args)
      # caller [expr]
      # Display the call stack of the current subroutine call
      # With expr: display stack frame at that depth (0 = current)
      # Returns false if no call stack or expr is out of range

      # Check for invalid options
      if args.any? { |arg| arg.start_with?('-') }
        puts "caller: #{args.first}: invalid option"
        return false
      end

      # Get the frame number (default 0)
      frame = 0
      if args.any?
        arg = args.first
        unless arg =~ /^\d+$/
          puts "caller: #{arg}: invalid number"
          return false
        end
        frame = arg.to_i
      end

      # Check if we have a call stack
      if @call_stack.empty?
        return false
      end

      # Check if frame is in range
      if frame >= @call_stack.length
        return false
      end

      # Get the frame (stack is stored with most recent first)
      # But caller 0 should be the immediate caller, so we need to reverse
      stack_frame = @call_stack[-(frame + 1)]
      return false unless stack_frame

      line_number, function_name, filename = stack_frame
      puts "#{line_number} #{function_name} #{filename}"
      true
    end

    def self.push_call_frame(line_number, function_name, filename)
      @call_stack.push([line_number, function_name, filename])
    end

    def self.pop_call_frame
      @call_stack.pop
    end

    def self.clear_call_stack
      @call_stack.clear
    end

    def self.run_complete(args)
      # complete [-abcdefgjksuv] [-o option] [-A action] [-G globpat] [-W wordlist]
      #          [-F function] [-C command] [-X filterpat] [-P prefix] [-S suffix]
      #          [-p] [-r] [name ...]
      # Define completion specifications for commands

      # Parse options
      print_mode = false
      remove_mode = false
      spec = {
        actions: [],
        wordlist: nil,
        function: nil,
        command: nil,
        globpat: nil,
        filterpat: nil,
        prefix: nil,
        suffix: nil,
        options: []
      }
      names = []

      # Action flags mapping
      action_flags = {
        'a' => :alias,
        'b' => :builtin,
        'c' => :command,
        'd' => :directory,
        'e' => :export,
        'f' => :file,
        'g' => :group,
        'j' => :job,
        'k' => :keyword,
        's' => :service,
        'u' => :user,
        'v' => :variable
      }

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-') && names.empty?
          case arg
          when '-p'
            print_mode = true
          when '-r'
            remove_mode = true
          when '-o'
            i += 1
            spec[:options] << args[i] if args[i]
          when '-A'
            i += 1
            spec[:actions] << args[i].to_sym if args[i]
          when '-G'
            i += 1
            spec[:globpat] = args[i]
          when '-W'
            i += 1
            spec[:wordlist] = args[i]
          when '-F'
            i += 1
            spec[:function] = args[i]
          when '-C'
            i += 1
            spec[:command] = args[i]
          when '-X'
            i += 1
            spec[:filterpat] = args[i]
          when '-P'
            i += 1
            spec[:prefix] = args[i]
          when '-S'
            i += 1
            spec[:suffix] = args[i]
          else
            # Handle combined flags like -df
            arg[1..].each_char do |c|
              if action_flags.key?(c)
                spec[:actions] << action_flags[c]
              else
                puts "complete: -#{c}: invalid option"
                return false
              end
            end
          end
        else
          names << arg
        end
        i += 1
      end

      # Print mode
      if print_mode
        if names.empty?
          # Print all completions
          @completions.each do |name, s|
            puts format_completion_spec(name, s)
          end
        else
          # Print specified completions
          names.each do |name|
            if @completions.key?(name)
              puts format_completion_spec(name, @completions[name])
            else
              puts "complete: #{name}: no completion specification"
              return false
            end
          end
        end
        return true
      end

      # Remove mode
      if remove_mode
        if names.empty?
          # Remove all completions
          @completions.clear
        else
          names.each do |name|
            @completions.delete(name)
          end
        end
        return true
      end

      # Define completions
      if names.empty?
        puts 'complete: usage: complete [-abcdefgjksuv] [-pr] [-o option] [-A action] [name ...]'
        return false
      end

      names.each do |name|
        @completions[name] = spec.dup
      end

      true
    end

    def self.format_completion_spec(name, spec)
      parts = ['complete']

      spec[:actions].each do |action|
        case action
        when :alias then parts << '-a'
        when :builtin then parts << '-b'
        when :command then parts << '-c'
        when :directory then parts << '-d'
        when :export then parts << '-e'
        when :file then parts << '-f'
        when :group then parts << '-g'
        when :job then parts << '-j'
        when :keyword then parts << '-k'
        when :service then parts << '-s'
        when :user then parts << '-u'
        when :variable then parts << '-v'
        else
          parts << "-A #{action}"
        end
      end

      spec[:options].each { |o| parts << "-o #{o}" }
      parts << "-G #{spec[:globpat]}" if spec[:globpat]
      parts << "-W '#{spec[:wordlist]}'" if spec[:wordlist]
      parts << "-F #{spec[:function]}" if spec[:function]
      parts << "-C #{spec[:command]}" if spec[:command]
      parts << "-X '#{spec[:filterpat]}'" if spec[:filterpat]
      parts << "-P '#{spec[:prefix]}'" if spec[:prefix]
      parts << "-S '#{spec[:suffix]}'" if spec[:suffix]

      parts << name
      parts.join(' ')
    end

    def self.run_compgen(args)
      # compgen [-abcdefgjksuv] [-o option] [-A action] [-G globpat] [-W wordlist]
      #         [-F function] [-C command] [-X filterpat] [-P prefix] [-S suffix] [word]
      # Generate completions matching word

      spec = {
        actions: [],
        wordlist: nil,
        function: nil,
        command: nil,
        globpat: nil,
        filterpat: nil,
        prefix: nil,
        suffix: nil,
        options: []
      }
      word = ''

      action_flags = {
        'a' => :alias,
        'b' => :builtin,
        'c' => :command,
        'd' => :directory,
        'e' => :export,
        'f' => :file,
        'g' => :group,
        'j' => :job,
        'k' => :keyword,
        's' => :service,
        'u' => :user,
        'v' => :variable
      }

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-')
          case arg
          when '-o'
            i += 1
            spec[:options] << args[i] if args[i]
          when '-A'
            i += 1
            spec[:actions] << args[i].to_sym if args[i]
          when '-G'
            i += 1
            spec[:globpat] = args[i]
          when '-W'
            i += 1
            spec[:wordlist] = args[i]
          when '-F'
            i += 1
            spec[:function] = args[i]
          when '-C'
            i += 1
            spec[:command] = args[i]
          when '-X'
            i += 1
            spec[:filterpat] = args[i]
          when '-P'
            i += 1
            spec[:prefix] = args[i]
          when '-S'
            i += 1
            spec[:suffix] = args[i]
          else
            arg[1..].each_char do |c|
              if action_flags.key?(c)
                spec[:actions] << action_flags[c]
              else
                puts "compgen: -#{c}: invalid option"
                return false
              end
            end
          end
        else
          word = arg
        end
        i += 1
      end

      completions = generate_completions(spec, word)

      completions.each { |c| puts c }
      !completions.empty?
    end

    def self.generate_completions(spec, word = '')
      results = []

      spec[:actions].each do |action|
        case action
        when :alias
          results.concat(@aliases.keys.select { |a| a.start_with?(word) })
        when :builtin
          results.concat(COMMANDS.select { |c| c.start_with?(word) })
        when :command
          # Commands from PATH
          ENV['PATH'].to_s.split(':').each do |dir|
            next unless Dir.exist?(dir)

            Dir.entries(dir).each do |entry|
              next if entry.start_with?('.')

              path = File.join(dir, entry)
              results << entry if entry.start_with?(word) && File.executable?(path)
            end
          rescue Errno::EACCES
            # Skip directories we can't read
          end
          results.concat(COMMANDS.select { |c| c.start_with?(word) })
        when :directory
          pattern = word.empty? ? '*' : "#{word}*"
          Dir.glob(pattern).each do |entry|
            results << entry if File.directory?(entry)
          end
        when :export
          ENV.keys.select { |k| k.start_with?(word) }.each { |k| results << k }
        when :file
          pattern = word.empty? ? '*' : "#{word}*"
          results.concat(Dir.glob(pattern))
        when :job
          JobManager.instance.all.each do |job|
            job_spec = "%#{job.id}"
            results << job_spec if job_spec.start_with?(word)
          end
        when :user
          begin
            Etc.passwd { |u| results << u.name if u.name.start_with?(word) }
          rescue StandardError
            # Etc may not be available
          end
        when :variable
          ENV.keys.select { |k| k.start_with?(word) }.each { |k| results << k }
        when :group
          begin
            Etc.group { |g| results << g.name if g.name.start_with?(word) }
          rescue StandardError
            # Etc may not be available
          end
        end
      end

      # Wordlist
      if spec[:wordlist]
        words = spec[:wordlist].split
        results.concat(words.select { |w| w.start_with?(word) })
      end

      # Glob pattern
      if spec[:globpat]
        results.concat(Dir.glob(spec[:globpat]).select { |f| f.start_with?(word) })
      end

      # Filter pattern
      if spec[:filterpat]
        pattern = Regexp.new(spec[:filterpat].gsub('*', '.*').gsub('?', '.'))
        results.reject! { |r| r.match?(pattern) }
      end

      # Add prefix/suffix
      if spec[:prefix] || spec[:suffix]
        results.map! do |r|
          "#{spec[:prefix]}#{r}#{spec[:suffix]}"
        end
      end

      results.uniq.sort
    end

    def self.get_completion_spec(name)
      @completions[name]
    end

    def self.clear_completions
      @completions.clear
    end

    # Valid completion options for compopt
    COMPLETION_OPTIONS = %w[
      bashdefault default dirnames filenames noquote nosort nospace plusdirs
    ].freeze

    def self.run_compopt(args)
      # compopt [-o option] [-DE] [+o option] [name ...]
      # Modify completion options for each name, or for the currently executing completion
      # -o option: Enable option
      # +o option: Disable option
      # -D: Apply to default completion (when no specific completion exists)
      # -E: Apply to empty command completion (when completing on empty line)

      enable_opts = []
      disable_opts = []
      names = []
      apply_default = false
      apply_empty = false

      i = 0
      while i < args.length
        arg = args[i]
        case arg
        when '-o'
          i += 1
          opt = args[i]
          if opt && COMPLETION_OPTIONS.include?(opt)
            enable_opts << opt
          elsif opt
            $stderr.puts "compopt: #{opt}: invalid option name"
            return false
          end
        when '+o'
          i += 1
          opt = args[i]
          if opt && COMPLETION_OPTIONS.include?(opt)
            disable_opts << opt
          elsif opt
            $stderr.puts "compopt: #{opt}: invalid option name"
            return false
          end
        when '-D'
          apply_default = true
        when '-E'
          apply_empty = true
        when /\A-o(.+)/
          # -oOPTION (combined form)
          opt = $1
          if COMPLETION_OPTIONS.include?(opt)
            enable_opts << opt
          else
            $stderr.puts "compopt: #{opt}: invalid option name"
            return false
          end
        when /\A\+o(.+)/
          # +oOPTION (combined form)
          opt = $1
          if COMPLETION_OPTIONS.include?(opt)
            disable_opts << opt
          else
            $stderr.puts "compopt: #{opt}: invalid option name"
            return false
          end
        else
          names << arg
        end
        i += 1
      end

      # If no options specified, print current options
      if enable_opts.empty? && disable_opts.empty?
        return print_compopt_options(names, apply_default, apply_empty)
      end

      # Apply options
      if names.empty? && !apply_default && !apply_empty
        # Apply to currently executing completion
        enable_opts.each { |opt| @current_completion_options.add(opt) }
        disable_opts.each { |opt| @current_completion_options.delete(opt) }
      else
        # Apply to named commands
        targets = []
        targets << :default if apply_default
        targets << :empty if apply_empty
        targets.concat(names)

        targets.each do |name|
          @completion_options[name] ||= Set.new
          enable_opts.each { |opt| @completion_options[name].add(opt) }
          disable_opts.each { |opt| @completion_options[name].delete(opt) }
        end
      end

      true
    end

    def self.print_compopt_options(names, apply_default, apply_empty)
      targets = []
      targets << :default if apply_default
      targets << :empty if apply_empty
      targets.concat(names)

      if targets.empty?
        # Print current completion options
        if @current_completion_options.empty?
          puts 'compopt: no options set'
        else
          @current_completion_options.each { |opt| puts "compopt -o #{opt}" }
        end
      else
        targets.each do |name|
          opts = @completion_options[name] || Set.new
          display_name = name.is_a?(Symbol) ? "-#{name.to_s[0].upcase}" : name
          if opts.empty?
            puts "compopt #{display_name}: no options"
          else
            opts.each { |opt| puts "compopt -o #{opt} #{display_name}" }
          end
        end
      end
      true
    end

    def self.get_completion_options(name)
      @completion_options[name] || Set.new
    end

    def self.completion_option?(name, option)
      (@completion_options[name] || Set.new).include?(option)
    end

    # Readline function names for -l option
    READLINE_FUNCTIONS = %w[
      abort accept-line backward-char backward-delete-char backward-kill-line
      backward-kill-word backward-word beginning-of-history beginning-of-line
      call-last-kbd-macro capitalize-word character-search character-search-backward
      clear-screen complete delete-char delete-horizontal-space digit-argument
      do-lowercase-version downcase-word dump-functions dump-macros dump-variables
      emacs-editing-mode end-of-history end-of-line exchange-point-and-mark
      forward-backward-delete-char forward-char forward-search-history forward-word
      history-search-backward history-search-forward insert-comment insert-completions
      kill-line kill-region kill-whole-line kill-word menu-complete menu-complete-backward
      next-history non-incremental-forward-search-history non-incremental-reverse-search-history
      overwrite-mode possible-completions previous-history quoted-insert
      re-read-init-file redraw-current-line reverse-search-history revert-line
      self-insert set-mark shell-backward-kill-word shell-backward-word shell-expand-line
      shell-forward-word shell-kill-word start-kbd-macro tilde-expand transpose-chars
      transpose-words undo universal-argument unix-filename-rubout unix-line-discard
      unix-word-rubout upcase-word vi-append-eol vi-append-mode vi-arg-digit
      vi-bWord vi-back-to-indent vi-bword vi-change-case vi-change-char vi-change-to
      vi-char-search vi-column vi-complete vi-delete vi-delete-to vi-eWord vi-editing-mode
      vi-end-word vi-eof-maybe vi-eword vi-fWord vi-fetch-history vi-first-print
      vi-fword vi-goto-mark vi-insert-beg vi-insertion-mode vi-match vi-movement-mode
      vi-next-word vi-overstrike vi-overstrike-delete vi-prev-word vi-put vi-redo
      vi-replace vi-rubout vi-search vi-search-again vi-set-mark vi-subst vi-tilde-expand
      vi-undo vi-yank-arg vi-yank-to yank yank-last-arg yank-nth-arg yank-pop
    ].freeze

    # Readline variable names for -v/-V options
    READLINE_VARIABLES_LIST = %w[
      bell-style bind-tty-special-chars blink-matching-paren colored-completion-prefix
      colored-stats comment-begin completion-display-width completion-ignore-case
      completion-map-case completion-prefix-display-length completion-query-items
      convert-meta disable-completion echo-control-characters editing-mode
      emacs-mode-string enable-bracketed-paste enable-keypad expand-tilde
      history-preserve-point history-size horizontal-scroll-mode input-meta
      isearch-terminators keymap keyseq-timeout mark-directories mark-modified-lines
      mark-symlinked-directories match-hidden-files menu-complete-display-prefix
      output-meta page-completions print-completions-horizontally revert-all-at-newline
      show-all-if-ambiguous show-all-if-unmodified show-mode-in-prompt skip-completed-text
      vi-cmd-mode-string vi-ins-mode-string visible-stats
    ].freeze

    def self.run_bind(args)
      # bind [-m keymap] [-lpsvPSVX]
      # bind [-m keymap] [-q function] [-u function] [-r keyseq]
      # bind [-m keymap] -f filename
      # bind [-m keymap] -x keyseq:shell-command
      # bind [-m keymap] keyseq:function-name

      keymap = 'emacs'  # default keymap
      list_functions = false
      print_bindings = false
      print_bindings_readable = false
      print_macros = false
      print_macros_readable = false
      print_variables = false
      print_variables_readable = false
      print_shell_bindings = false
      query_function = nil
      unbind_function = nil
      remove_keyseq = nil
      read_file = nil
      shell_command_binding = nil
      bindings_to_add = []

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-')
          case arg
          when '-m'
            i += 1
            keymap = args[i] if args[i]
          when '-l'
            list_functions = true
          when '-p'
            print_bindings_readable = true
          when '-P'
            print_bindings = true
          when '-s'
            print_macros_readable = true
          when '-S'
            print_macros = true
          when '-v'
            print_variables_readable = true
          when '-V'
            print_variables = true
          when '-X'
            print_shell_bindings = true
          when '-q'
            i += 1
            query_function = args[i]
          when '-u'
            i += 1
            unbind_function = args[i]
          when '-r'
            i += 1
            remove_keyseq = args[i]
          when '-f'
            i += 1
            read_file = args[i]
          when '-x'
            i += 1
            shell_command_binding = args[i]
          else
            # Handle combined flags
            arg[1..].each_char do |c|
              case c
              when 'l' then list_functions = true
              when 'p' then print_bindings_readable = true
              when 'P' then print_bindings = true
              when 's' then print_macros_readable = true
              when 'S' then print_macros = true
              when 'v' then print_variables_readable = true
              when 'V' then print_variables = true
              when 'X' then print_shell_bindings = true
              else
                puts "bind: -#{c}: invalid option"
                return false
              end
            end
          end
        elsif arg.include?(':')
          # keyseq:function-name or keyseq:macro
          bindings_to_add << arg
        else
          puts "bind: #{arg}: invalid key binding"
          return false
        end
        i += 1
      end

      # List all readline function names
      if list_functions
        READLINE_FUNCTIONS.each { |f| puts f }
        return true
      end

      # Print key bindings in reusable format
      if print_bindings_readable
        @key_bindings.each do |keyseq, binding|
          next if binding[:type] == :macro || binding[:type] == :command

          puts "\"#{escape_keyseq(keyseq)}\": #{binding[:value]}"
        end
        return true
      end

      # Print key bindings with function names
      if print_bindings
        @key_bindings.each do |keyseq, binding|
          next if binding[:type] == :macro || binding[:type] == :command

          puts "#{escape_keyseq(keyseq)} can be found in #{binding[:value]}."
        end
        return true
      end

      # Print macros in reusable format
      if print_macros_readable
        @key_bindings.each do |keyseq, binding|
          next unless binding[:type] == :macro

          puts "\"#{escape_keyseq(keyseq)}\": \"#{binding[:value]}\""
        end
        return true
      end

      # Print macros
      if print_macros
        @key_bindings.each do |keyseq, binding|
          next unless binding[:type] == :macro

          puts "#{escape_keyseq(keyseq)} outputs #{binding[:value]}"
        end
        return true
      end

      # Print readline variables in reusable format
      if print_variables_readable
        READLINE_VARIABLES_LIST.each do |var|
          value = @readline_variables[var] || 'off'
          puts "set #{var} #{value}"
        end
        return true
      end

      # Print readline variables
      if print_variables
        READLINE_VARIABLES_LIST.each do |var|
          value = @readline_variables[var] || 'off'
          puts "#{var} is set to `#{value}'"
        end
        return true
      end

      # Print shell command bindings
      if print_shell_bindings
        @key_bindings.each do |keyseq, binding|
          next unless binding[:type] == :command

          puts "\"#{escape_keyseq(keyseq)}\": \"#{binding[:value]}\""
        end
        return true
      end

      # Query which keys invoke a function
      if query_function
        found = false
        @key_bindings.each do |keyseq, binding|
          if binding[:value] == query_function && binding[:type] == :function
            puts "#{query_function} can be invoked via \"#{escape_keyseq(keyseq)}\"."
            found = true
          end
        end
        puts "#{query_function} is not bound to any keys." unless found
        return true
      end

      # Unbind all keys for a function
      if unbind_function
        @key_bindings.delete_if { |_, binding| binding[:value] == unbind_function }
        return true
      end

      # Remove binding for keyseq
      if remove_keyseq
        @key_bindings.delete(remove_keyseq)
        return true
      end

      # Read bindings from file
      if read_file
        unless File.exist?(read_file)
          puts "bind: #{read_file}: cannot read: No such file or directory"
          return false
        end

        File.readlines(read_file).each do |line|
          line = line.strip
          next if line.empty? || line.start_with?('#')

          if line.start_with?('set ')
            # Variable setting: set variable value
            parts = line.split(' ', 3)
            if parts.length >= 3
              @readline_variables[parts[1]] = parts[2]
            end
          elsif line.include?(':')
            parse_and_add_binding(line)
          end
        end
        return true
      end

      # Add shell command binding
      if shell_command_binding
        if shell_command_binding.include?(':')
          keyseq, command = shell_command_binding.split(':', 2)
          keyseq = unescape_keyseq(keyseq.delete('"'))
          command = command.delete('"').strip
          @key_bindings[keyseq] = {type: :command, value: command, keymap: keymap}
        else
          puts "bind: #{shell_command_binding}: invalid key binding"
          return false
        end
        return true
      end

      # Add bindings from arguments
      bindings_to_add.each do |binding|
        parse_and_add_binding(binding, keymap)
      end

      true
    end

    def self.parse_and_add_binding(binding_str, keymap = 'emacs')
      keyseq, value = binding_str.split(':', 2)
      return unless keyseq && value

      keyseq = unescape_keyseq(keyseq.delete('"').strip)
      value = value.strip

      # Determine if it's a function or macro
      if value.start_with?('"') && value.end_with?('"')
        # Macro
        @key_bindings[keyseq] = {type: :macro, value: value[1..-2], keymap: keymap}
      else
        # Function
        @key_bindings[keyseq] = {type: :function, value: value, keymap: keymap}
      end
    end

    def self.escape_keyseq(keyseq)
      keyseq.gsub("\e", '\\e').gsub("\C-a", '\\C-a').gsub("\t", '\\t').gsub("\n", '\\n')
    end

    def self.unescape_keyseq(keyseq)
      result = keyseq.dup

      # Handle escape sequences
      result.gsub!('\\e', "\e")
      result.gsub!('\\t', "\t")
      result.gsub!('\\n', "\n")
      result.gsub!('\\r', "\r")

      # Handle control characters \C-x format
      result.gsub!(/\\C-([a-z@\[\]\\^_])/) do |_|
        char = ::Regexp.last_match(1)
        (char.ord - 'a'.ord + 1).chr
      end

      # Handle control characters \C-? format for DEL
      result.gsub!('\\C-?', "\x7F")

      result
    end

    def self.get_key_binding(keyseq)
      @key_bindings[keyseq]
    end

    def self.clear_key_bindings
      @key_bindings.clear
      @readline_variables.clear
    end

    def self.run_hash(args)
      # hash [-lr] [-p path] [-dt] [name ...]
      # -r: forget all cached paths
      # -d: forget cached path for each name
      # -l: list in reusable format
      # -p path: cache name with given path
      # -t: print cached path for each name

      if args.empty?
        # List all cached paths
        if @command_hash.empty?
          puts 'hash: hash table empty'
        else
          @command_hash.each do |name, path|
            puts "#{name}=#{path}"
          end
        end
        return true
      end

      # Parse options
      clear_all = false
      delete_mode = false
      list_mode = false
      print_mode = false
      set_path = nil
      names = []
      i = 0

      while i < args.length
        arg = args[i]

        if arg == '-r' && names.empty?
          clear_all = true
          i += 1
        elsif arg == '-d' && names.empty?
          delete_mode = true
          i += 1
        elsif arg == '-l' && names.empty?
          list_mode = true
          i += 1
        elsif arg == '-t' && names.empty?
          print_mode = true
          i += 1
        elsif arg == '-p' && names.empty? && i + 1 < args.length
          set_path = args[i + 1]
          i += 2
        elsif arg.start_with?('-') && names.empty?
          # Handle combined flags
          arg[1..].each_char do |c|
            case c
            when 'r' then clear_all = true
            when 'd' then delete_mode = true
            when 'l' then list_mode = true
            when 't' then print_mode = true
            else
              puts "hash: -#{c}: invalid option"
              return false
            end
          end
          i += 1
        else
          names << arg
          i += 1
        end
      end

      # Handle -r (clear all)
      if clear_all
        @command_hash.clear
        return true
      end

      # Handle -l (list mode) with no names
      if list_mode && names.empty?
        @command_hash.each do |name, path|
          puts "hash -p #{path} #{name}"
        end
        return true
      end

      # Handle names
      all_found = true

      if names.empty? && !set_path
        # No names and no path to set, just list
        if @command_hash.empty?
          puts 'hash: hash table empty'
        else
          @command_hash.each do |name, path|
            puts "#{name}=#{path}"
          end
        end
        return true
      end

      names.each do |name|
        if delete_mode
          # Forget cached path
          if @command_hash.key?(name)
            @command_hash.delete(name)
          else
            puts "hash: #{name}: not found"
            all_found = false
          end
        elsif print_mode
          # Print cached path
          if @command_hash.key?(name)
            puts @command_hash[name]
          else
            # Try to find and cache
            path = find_in_path(name)
            if path
              @command_hash[name] = path
              puts path
            else
              puts "hash: #{name}: not found"
              all_found = false
            end
          end
        elsif set_path
          # Set specific path
          @command_hash[name] = set_path
        else
          # Cache the command
          path = find_in_path(name)
          if path
            @command_hash[name] = path
          else
            puts "hash: #{name}: not found"
            all_found = false
          end
        end
      end

      all_found
    end

    def self.hash_lookup(name)
      @command_hash[name]
    end

    def self.hash_store(name, path)
      @command_hash[name] = path
    end

    def self.clear_hash
      @command_hash.clear
    end

    def self.run_times(_args)
      # times
      # Display accumulated user and system times for shell and children
      # Format: user system (for shell), then user system (for children)

      t = Process.times

      # Format times as minutes and seconds
      format_time = ->(seconds) {
        mins = (seconds / 60).to_i
        secs = seconds % 60
        format('%dm%0.3fs', mins, secs)
      }

      # Shell times (user and system)
      puts "#{format_time.call(t.utime)} #{format_time.call(t.stime)}"
      # Children times (user and system)
      puts "#{format_time.call(t.cutime)} #{format_time.call(t.cstime)}"

      true
    end

    def self.run_exec(args)
      # exec [-cl] [-a name] [command [arguments]]
      # -c: execute command with empty environment
      # -l: place dash at beginning of argv[0] (login shell)
      # -a name: pass name as argv[0]
      # If no command, exec succeeds but does nothing (useful for redirects)

      clear_env = false
      login_shell = false
      argv0 = nil
      cmd_args = []
      i = 0

      while i < args.length
        arg = args[i]

        if arg == '-c' && cmd_args.empty?
          clear_env = true
          i += 1
        elsif arg == '-l' && cmd_args.empty?
          login_shell = true
          i += 1
        elsif arg == '-a' && cmd_args.empty? && i + 1 < args.length
          argv0 = args[i + 1]
          i += 2
        elsif arg == '-cl' || arg == '-lc' && cmd_args.empty?
          clear_env = true
          login_shell = true
          i += 1
        elsif arg.start_with?('-') && cmd_args.empty? && arg.length > 1
          # Handle combined flags like -cla
          arg[1..].each_char do |c|
            case c
            when 'c' then clear_env = true
            when 'l' then login_shell = true
            else
              puts "exec: -#{c}: invalid option"
              return false
            end
          end
          i += 1
        else
          cmd_args = args[i..]
          break
        end
      end

      # If no command, just return success (useful for fd redirects only)
      return true if cmd_args.empty?

      command = cmd_args.first
      command_args = cmd_args[1..] || []

      # Find the command in PATH if not absolute
      unless command.include?('/')
        path = find_in_path(command)
        if path
          command = path
        else
          puts "exec: #{cmd_args.first}: not found"
          return false
        end
      end

      # Prepare argv[0]
      if argv0
        exec_argv0 = argv0
      elsif login_shell
        exec_argv0 = "-#{File.basename(command)}"
      else
        exec_argv0 = File.basename(command)
      end

      # Run exit traps before exec
      run_exit_traps

      # Execute
      begin
        if clear_env
          # Clear environment and exec
          exec([command, exec_argv0], *command_args, unsetenv_others: true)
        else
          exec([command, exec_argv0], *command_args)
        end
      rescue Errno::ENOENT
        puts "exec: #{cmd_args.first}: not found"
        false
      rescue Errno::EACCES
        puts "exec: #{cmd_args.first}: permission denied"
        false
      rescue => e
        puts "exec: #{e.message}"
        false
      end
    end

    def self.run_umask(args)
      # umask [-p] [-S] [mode]
      # -p: output in a form that can be reused as input
      # -S: output in symbolic form
      # mode: octal or symbolic mode

      symbolic = false
      print_reusable = false
      mode_arg = nil

      args.each do |arg|
        case arg
        when '-S'
          symbolic = true
        when '-p'
          print_reusable = true
        else
          mode_arg = arg
        end
      end

      if mode_arg
        # Set umask
        new_mask = parse_umask(mode_arg)
        if new_mask.nil?
          puts "umask: #{mode_arg}: invalid mode"
          return false
        end
        File.umask(new_mask)
        true
      else
        # Display current umask
        current = File.umask
        if symbolic
          # Symbolic format: u=rwx,g=rx,o=rx
          sym = umask_to_symbolic(current)
          if print_reusable
            puts "umask -S #{sym}"
          else
            puts sym
          end
        else
          # Octal format
          if print_reusable
            puts "umask #{format('%04o', current)}"
          else
            puts format('%04o', current)
          end
        end
        true
      end
    end

    def self.parse_umask(mode)
      if mode =~ /\A[0-7]{1,4}\z/
        # Octal mode
        mode.to_i(8)
      elsif mode =~ /\A[ugoa]*[=+-][rwx]*\z/ || mode.include?(',')
        # Symbolic mode
        parse_symbolic_umask(mode)
      else
        nil
      end
    end

    def self.parse_symbolic_umask(mode)
      current = File.umask
      # Convert umask to permission bits (inverted)
      perms = 0o777 - current

      mode.split(',').each do |clause|
        match = clause.match(/\A([ugoa]*)([-+=])([rwx]*)\z/)
        return nil unless match

        who = match[1]
        op = match[2]
        what = match[3]

        who = 'ugo' if who.empty? || who == 'a'

        # Calculate permission bits
        bits = 0
        bits |= 4 if what.include?('r')
        bits |= 2 if what.include?('w')
        bits |= 1 if what.include?('x')

        who.each_char do |w|
          shift = case w
                  when 'u' then 6
                  when 'g' then 3
                  when 'o' then 0
                  end
          next unless shift

          case op
          when '='
            # Clear and set
            perms &= ~(7 << shift)
            perms |= (bits << shift)
          when '+'
            perms |= (bits << shift)
          when '-'
            perms &= ~(bits << shift)
          end
        end
      end

      # Convert back to umask
      0o777 - perms
    end

    def self.umask_to_symbolic(mask)
      # Convert umask to symbolic format
      perms = 0o777 - mask

      parts = []
      [['u', 6], ['g', 3], ['o', 0]].each do |who, shift|
        bits = (perms >> shift) & 7
        p = +''
        p << 'r' if (bits & 4) != 0
        p << 'w' if (bits & 2) != 0
        p << 'x' if (bits & 1) != 0
        parts << "#{who}=#{p}"
      end

      parts.join(',')
    end

    def self.run_kill(args)
      # kill [-s signal | -signal] pid|%jobspec ...
      # kill -l [signal]
      # Send signals to processes or jobs

      if args.empty?
        puts 'kill: usage: kill [-s signal | -signal] pid|%jobspec ... or kill -l [signal]'
        return false
      end

      # Handle -l (list signals)
      if args.first == '-l'
        if args.length == 1
          # List all signals
          Signal.list.each do |name, num|
            puts "#{num}) SIG#{name}" unless name == 'EXIT'
          end
        else
          # Convert signal number to name or vice versa
          args[1..].each do |arg|
            if arg =~ /\A\d+\z/
              # Number to name
              num = arg.to_i
              name = Signal.list.key(num)
              puts name || num
            else
              # Name to number
              sig_name = arg.upcase.delete_prefix('SIG')
              num = Signal.list[sig_name]
              puts num || arg
            end
          end
        end
        return true
      end

      # Parse signal specification
      signal = 'TERM'  # Default signal
      pids = []
      i = 0

      while i < args.length
        arg = args[i]

        if arg == '-s' && i + 1 < args.length
          # -s SIGNAL
          signal = args[i + 1].upcase.delete_prefix('SIG')
          i += 2
        elsif arg =~ /\A-(\d+)\z/
          # -N (signal number)
          signal = $1.to_i
          i += 1
        elsif arg =~ /\A-([A-Za-z][A-Za-z0-9]*)\z/
          # -SIGNAL (signal name)
          signal = $1.upcase.delete_prefix('SIG')
          i += 1
        else
          pids << arg
          i += 1
        end
      end

      if pids.empty?
        puts 'kill: usage: kill [-s signal | -signal] pid|%jobspec ...'
        return false
      end

      # Normalize signal
      sig = if signal.is_a?(Integer)
              signal
            else
              Signal.list[signal] || Signal.list[signal.delete_prefix('SIG')]
            end

      unless sig
        puts "kill: #{signal}: invalid signal specification"
        return false
      end

      all_success = true
      manager = JobManager.instance

      pids.each do |pid_arg|
        begin
          if pid_arg.start_with?('%')
            # Job spec
            job_id = pid_arg[1..].to_i
            job = manager.get(job_id)
            unless job
              puts "kill: %#{job_id}: no such job"
              all_success = false
              next
            end
            Process.kill(sig, -job.pgid)
          else
            # PID
            pid = pid_arg.to_i
            Process.kill(sig, pid)
          end
        rescue Errno::ESRCH
          puts "kill: (#{pid_arg}) - No such process"
          all_success = false
        rescue Errno::EPERM
          puts "kill: (#{pid_arg}) - Operation not permitted"
          all_success = false
        end
      end

      all_success
    end

    def self.run_wait(args)
      # wait [pid|%jobspec ...]
      # Wait for background jobs to complete
      # With no args, waits for all background jobs
      # Returns exit status of last job waited for

      manager = JobManager.instance
      last_status = true

      if args.empty?
        # Wait for all background jobs
        jobs = manager.active
        if jobs.empty?
          # No tracked jobs, but there may still be child processes
          # (e.g., when monitor mode is off). Wait for all children.
          begin
            loop do
              _, status = Process.wait2(-1)
              last_status = status.success?
            end
          rescue Errno::ECHILD
            # No more children
          end
          return last_status
        end

        jobs.each do |job|
          begin
            _, status = Process.wait2(job.pid)
            manager.update_status(job.pid, status)
            manager.remove(job.id)
            last_status = status.success?
          rescue Errno::ECHILD
            # Process already gone
            manager.remove(job.id)
          end
        end
      else
        # Wait for specific jobs
        args.each do |arg|
          job = nil

          if arg.start_with?('%')
            # Job spec
            job_id = arg[1..].to_i
            job = manager.get(job_id)
            unless job
              puts "wait: %#{job_id}: no such job"
              last_status = false
              next
            end
          else
            # PID
            pid = arg.to_i
            job = manager.find_by_pid(pid)
            unless job
              # Try waiting for any child with this PID
              begin
                _, status = Process.wait2(pid)
                last_status = status.success?
                next
              rescue Errno::ECHILD
                puts "wait: pid #{pid} is not a child of this shell"
                last_status = false
                next
              end
            end
          end

          if job
            begin
              _, status = Process.wait2(job.pid)
              manager.update_status(job.pid, status)
              manager.remove(job.id)
              last_status = status.success?
            rescue Errno::ECHILD
              manager.remove(job.id)
            end
          end
        end
      end

      last_status
    end

    def self.run_builtin(args)
      # builtin command [arguments...]
      # Run a shell builtin directly, bypassing functions and aliases
      # Returns error if command is not a builtin

      if args.empty?
        puts 'builtin: usage: builtin command [arguments]'
        return false
      end

      cmd_name = args.first
      cmd_args = args[1..] || []

      unless builtin?(cmd_name)
        puts "builtin: #{cmd_name}: not a shell builtin"
        return false
      end

      run(cmd_name, cmd_args)
    end

    def self.run_command(args)
      # command [-pVv] command [arguments...]
      # -p: use default PATH to search for command
      # -v: print pathname or command type (similar to type -t)
      # -V: print description (similar to type)
      # Without flags: execute command bypassing functions and aliases

      if args.empty?
        puts 'command: usage: command [-pVv] command [arguments]'
        return false
      end

      use_default_path = false
      print_path = false
      print_description = false
      cmd_args = []

      i = 0
      while i < args.length
        arg = args[i]
        if arg.start_with?('-') && arg.length > 1 && cmd_args.empty?
          arg[1..].each_char do |c|
            case c
            when 'p' then use_default_path = true
            when 'v' then print_path = true
            when 'V' then print_description = true
            else
              puts "command: -#{c}: invalid option"
              return false
            end
          end
        else
          cmd_args = args[i..]
          break
        end
        i += 1
      end

      if cmd_args.empty?
        puts 'command: usage: command [-pVv] command [arguments]'
        return false
      end

      cmd_name = cmd_args.first

      # Handle -v flag: print path or type
      if print_path
        if builtin?(cmd_name)
          puts cmd_name
          return true
        end
        path = find_in_path(cmd_name)
        if path
          puts path
          return true
        end
        return false
      end

      # Handle -V flag: print description
      if print_description
        if builtin?(cmd_name)
          puts "#{cmd_name} is a shell builtin"
          return true
        end
        path = find_in_path(cmd_name)
        if path
          puts "#{cmd_name} is #{path}"
          return true
        end
        puts "command: #{cmd_name}: not found"
        return false
      end

      # Execute command bypassing functions and aliases
      if @command_executor
        @command_executor.call(cmd_args)
        true
      else
        # Fallback: just use regular executor with the command
        # This won't bypass functions but at least runs something
        @executor&.call(cmd_args.join(' '))
        true
      end
    end

    def self.run_eval(args)
      # eval [arg ...]
      # Concatenate arguments and execute as a shell command
      return true if args.empty?

      command = args.join(' ')

      unless @executor
        puts 'eval: executor not configured'
        return false
      end

      begin
        @executor.call(command)
        true
      rescue => e
        puts "eval: #{e.message}"
        false
      end
    end

    def self.run_which(args)
      # which [-a] name [name ...]
      # -a: print all matching executables in PATH, not just the first

      if args.empty?
        puts 'which: usage: which [-a] name [name ...]'
        return false
      end

      # Parse options
      show_all = false
      names = []

      args.each do |arg|
        if arg == '-a'
          show_all = true
        else
          names << arg
        end
      end

      if names.empty?
        puts 'which: usage: which [-a] name [name ...]'
        return false
      end

      all_found = true

      names.each do |name|
        if show_all
          paths = find_all_in_path(name)
          if paths.empty?
            puts "#{name} not found"
            all_found = false
          else
            paths.each { |p| puts p }
          end
        else
          path = find_in_path(name)
          if path
            puts path
          else
            puts "#{name} not found"
            all_found = false
          end
        end
      end

      all_found
    end

    def self.run_read(args)
      # Options
      opts = {
        prompt: nil,
        array_name: nil,
        delimiter: "\n",
        use_readline: false,
        initial_text: nil,
        nchars: nil,
        nchars_exact: nil,
        raw: false,
        silent: false,
        timeout: nil,
        fd: nil
      }
      vars = []

      # Parse options
      i = 0
      while i < args.length
        arg = args[i]
        case arg
        when '-a'
          opts[:array_name] = args[i + 1]
          i += 2
        when '-d'
          delim = args[i + 1]
          opts[:delimiter] = delim&.slice(0, 1) || "\n"
          i += 2
        when '-e'
          opts[:use_readline] = true
          i += 1
        when '-i'
          opts[:initial_text] = args[i + 1]
          i += 2
        when '-n'
          opts[:nchars] = args[i + 1]&.to_i
          i += 2
        when '-N'
          opts[:nchars_exact] = args[i + 1]&.to_i
          i += 2
        when '-p'
          opts[:prompt] = args[i + 1]
          i += 2
        when '-r'
          opts[:raw] = true
          i += 1
        when '-s'
          opts[:silent] = true
          i += 1
        when '-t'
          opts[:timeout] = args[i + 1]&.to_f
          i += 2
        when '-u'
          opts[:fd] = args[i + 1]&.to_i
          i += 2
        else
          vars << arg
          i += 1
        end
      end

      # Default variable is REPLY (unless using array mode)
      vars << 'REPLY' if vars.empty? && opts[:array_name].nil?

      # Read input
      line = read_input_line(opts)
      return false if line.nil?

      # Process backslash escapes unless raw mode
      unless opts[:raw]
        line = process_read_escapes(line)
      end

      # Store in array or variables
      if opts[:array_name]
        store_read_array(opts[:array_name], line)
      elsif opts[:nchars_exact]
        # -N mode: store raw content without splitting
        vars.each { |var| ENV[var] = line }
      else
        store_read_variables(vars, line)
      end

      true
    end

    def self.read_input_line(opts)
      input_stream = opts[:fd] ? IO.new(opts[:fd]) : $stdin

      # Use readline if -e specified
      if opts[:use_readline] && $stdin.tty?
        return read_with_readline(opts)
      end

      # Display prompt
      if opts[:prompt]
        $stderr.print opts[:prompt]
        $stderr.flush
      end

      # Handle silent mode
      if opts[:silent] && $stdin.tty?
        return read_silent(input_stream, opts)
      end

      # Handle timeout
      if opts[:timeout]
        return read_with_timeout(input_stream, opts)
      end

      # Handle character count modes
      if opts[:nchars_exact]
        return read_exact_chars(input_stream, opts[:nchars_exact])
      elsif opts[:nchars]
        return read_nchars(input_stream, opts[:nchars], opts[:delimiter])
      end

      # Normal line reading with custom delimiter
      read_until_delimiter(input_stream, opts[:delimiter])
    end

    def self.read_with_readline(opts)
      prompt = opts[:prompt] || ''

      if opts[:initial_text]
        # Pre-fill the input buffer
        Reline.pre_input_hook = -> {
          Reline.insert_text(opts[:initial_text])
          Reline.pre_input_hook = nil
        }
      end

      begin
        line = Reline.readline(prompt, false)
        return nil unless line
        line
      rescue Interrupt
        puts
        return nil
      end
    end

    def self.read_silent(input_stream, opts)
      line = +''
      delimiter = opts[:delimiter]
      nchars = opts[:nchars] || opts[:nchars_exact]

      begin
        input_stream.noecho do |io|
          if nchars
            nchars.times do
              char = io.getc
              break unless char
              break if char == delimiter && !opts[:nchars_exact]
              line << char
            end
          else
            loop do
              char = io.getc
              break unless char
              break if char == delimiter
              line << char
            end
          end
        end
        puts if $stdin.tty?  # Print newline after silent input
        line
      rescue Errno::ENOTTY
        # Not a terminal, fall back to normal read
        if nchars
          input_stream.read(nchars)&.chomp(delimiter)
        else
          read_until_delimiter(input_stream, delimiter)
        end
      end
    end

    def self.read_with_timeout(input_stream, opts)
      begin
        Timeout.timeout(opts[:timeout]) do
          if opts[:nchars_exact]
            read_exact_chars(input_stream, opts[:nchars_exact])
          elsif opts[:nchars]
            read_nchars(input_stream, opts[:nchars], opts[:delimiter])
          else
            read_until_delimiter(input_stream, opts[:delimiter])
          end
        end
      rescue Timeout::Error
        nil
      end
    end

    def self.read_exact_chars(input_stream, count)
      # -N: read exactly count chars, ignoring delimiters
      input_stream.read(count)
    end

    def self.read_nchars(input_stream, count, delimiter)
      # -n: read up to count chars or until delimiter
      line = +''
      count.times do
        char = input_stream.getc
        break unless char
        break if char == delimiter
        line << char
      end
      line
    end

    def self.read_until_delimiter(input_stream, delimiter)
      if delimiter == "\n"
        line = input_stream.gets
        return nil unless line
        line.chomp
      else
        line = +''
        loop do
          char = input_stream.getc
          break unless char
          break if char == delimiter
          line << char
        end
        line.empty? && input_stream.eof? ? nil : line
      end
    end

    def self.process_read_escapes(line)
      # Process backslash escapes (line continuation)
      # In read without -r, backslash at end of line continues to next line
      # and backslash before any char removes special meaning
      result = +''
      i = 0
      while i < line.length
        if line[i] == '\\'
          if i + 1 < line.length
            # Backslash escapes next character
            result << line[i + 1]
            i += 2
          else
            # Trailing backslash - in real bash this would continue reading
            # For simplicity, we just skip it
            i += 1
          end
        else
          result << line[i]
          i += 1
        end
      end
      result
    end

    def self.store_read_array(array_name, line)
      # Split line into words and store as array
      words = line.split
      clear_read_array(array_name)

      words.each_with_index do |word, idx|
        ENV["#{array_name}_#{idx}"] = word
      end
      ENV["#{array_name}_LENGTH"] = words.length.to_s
    end

    def self.clear_read_array(array_name)
      # Clear existing array elements
      length = ENV["#{array_name}_LENGTH"]&.to_i || 0
      length.times do |i|
        ENV.delete("#{array_name}_#{i}")
      end
      ENV.delete("#{array_name}_LENGTH")
    end

    def self.store_read_variables(vars, line)
      # If only one variable, assign the whole line (trimmed)
      if vars.length == 1
        ENV[vars[0]] = line.strip
        return
      end

      # Split into at most N parts where N = number of variables
      # This preserves whitespace in the last variable
      words = line.split(/\s+/, vars.length)

      vars.each_with_index do |var, idx|
        ENV[var] = words[idx]&.strip || ''
      end
    end

    def self.run_exit(args)
      code = args.first&.to_i || 0
      run_exit_traps
      throw :exit, code
    end

    def self.run_logout(args)
      # In bash, logout only works in login shells
      # For simplicity, we treat rubish as always being a login shell
      # and logout behaves the same as exit
      unless @shell_options['login_shell']
        # If not a login shell, warn but still exit (bash behavior varies)
        $stderr.puts 'logout: not login shell: use `exit\''
      end
      run_exit(args)
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
      unless set_option?('m')
        puts 'fg: no job control'
        return false
      end

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
      unless set_option?('m')
        puts 'bg: no job control'
        return false
      end

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

    # Documentation for builtin commands
    BUILTIN_HELP = {
      'cd' => {
        synopsis: 'cd [-L|-P] [dir]',
        description: 'Change the current directory to dir. If dir is not specified, change to $HOME.',
        options: {
          '-L' => 'follow symbolic links (default)',
          '-P' => 'use physical directory structure'
        }
      },
      'exit' => {
        synopsis: 'exit [n]',
        description: 'Exit the shell with a status of n. If n is omitted, exit status is that of the last command executed.'
      },
      'logout' => {
        synopsis: 'logout [n]',
        description: 'Exit a login shell with a status of n. If n is omitted, exit status is that of the last command executed. Prints a warning if not in a login shell.'
      },
      'jobs' => {
        synopsis: 'jobs [-l|-p] [jobspec ...]',
        description: 'List active jobs.',
        options: {
          '-l' => 'list process IDs in addition to normal info',
          '-p' => 'list process IDs only'
        }
      },
      'fg' => {
        synopsis: 'fg [job_spec]',
        description: 'Move job to the foreground. If job_spec is not present, the most recent job is used.'
      },
      'bg' => {
        synopsis: 'bg [job_spec ...]',
        description: 'Move jobs to the background. If job_spec is not present, the most recent job is used.'
      },
      'export' => {
        synopsis: 'export [-n] [name[=value] ...]',
        description: 'Set export attribute for shell variables. Exported variables are passed to child processes.',
        options: {
          '-n' => 'remove the export property from each name',
          '-p' => 'display all exported variables'
        }
      },
      'pwd' => {
        synopsis: 'pwd [-L|-P]',
        description: 'Print the current working directory.',
        options: {
          '-L' => 'print logical path (default)',
          '-P' => 'print physical path (resolve symlinks)'
        }
      },
      'history' => {
        synopsis: 'history [-c] [-d offset] [n]',
        description: 'Display or manipulate the history list.',
        options: {
          '-c' => 'clear the history list',
          '-d offset' => 'delete the history entry at offset',
          'n' => 'list only the last n entries'
        }
      },
      'alias' => {
        synopsis: 'alias [name[=value] ...]',
        description: 'Define or display aliases. Without arguments, print all aliases. With arguments, define aliases.'
      },
      'unalias' => {
        synopsis: 'unalias [-a] name [name ...]',
        description: 'Remove each name from the list of defined aliases.',
        options: {
          '-a' => 'remove all alias definitions'
        }
      },
      'source' => {
        synopsis: 'source filename [arguments]',
        description: 'Read and execute commands from filename in the current shell environment.'
      },
      '.' => {
        synopsis: '. filename [arguments]',
        description: 'Read and execute commands from filename in the current shell environment. Same as source.'
      },
      'shift' => {
        synopsis: 'shift [n]',
        description: 'Shift positional parameters to the left by n (default 1).'
      },
      'set' => {
        synopsis: 'set [--] [arg ...]',
        description: 'Set positional parameters, or display shell variables. With -- args, set $1, $2, etc.'
      },
      'return' => {
        synopsis: 'return [n]',
        description: 'Return from a shell function with return value n. If n is omitted, return status is that of the last command.'
      },
      'read' => {
        synopsis: 'read [-a array] [-d delim] [-e] [-i text] [-n nchars] [-N nchars] [-p prompt] [-r] [-s] [-t timeout] [-u fd] [name ...]',
        description: 'Read a line from standard input and split into fields. If no names are supplied, the line is stored in REPLY.',
        options: {
          '-a array' => 'store words in an indexed array (simulated via env vars: ARRAY_0, ARRAY_1, etc.)',
          '-d delim' => 'continue reading until first character of delim is read (instead of newline)',
          '-e' => 'use Readline for input (enables editing, history)',
          '-i text' => 'use text as initial text for Readline (requires -e)',
          '-n nchars' => 'return after reading nchars characters (or delimiter)',
          '-N nchars' => 'return after reading exactly nchars characters (ignores delimiter)',
          '-p prompt' => 'display prompt on stderr before reading',
          '-r' => 'raw mode: do not allow backslash escapes',
          '-s' => 'silent mode: do not echo input (for passwords)',
          '-t timeout' => 'time out and return failure after timeout seconds',
          '-u fd' => 'read from file descriptor fd instead of stdin'
        }
      },
      'echo' => {
        synopsis: 'echo [-n] [-e] [arg ...]',
        description: 'Write arguments to standard output.',
        options: {
          '-n' => 'do not append a newline',
          '-e' => 'enable interpretation of backslash escapes'
        }
      },
      'test' => {
        synopsis: 'test expr',
        description: 'Evaluate conditional expression and return 0 (true) or 1 (false).',
        options: {
          '-e file' => 'true if file exists',
          '-f file' => 'true if file is a regular file',
          '-d file' => 'true if file is a directory',
          '-r file' => 'true if file is readable',
          '-w file' => 'true if file is writable',
          '-x file' => 'true if file is executable',
          '-s file' => 'true if file has size greater than zero',
          '-z string' => 'true if string length is zero',
          '-n string' => 'true if string length is non-zero',
          's1 = s2' => 'true if strings are equal',
          's1 != s2' => 'true if strings are not equal',
          'n1 -eq n2' => 'true if integers are equal',
          'n1 -ne n2' => 'true if integers are not equal',
          'n1 -lt n2' => 'true if n1 < n2',
          'n1 -le n2' => 'true if n1 <= n2',
          'n1 -gt n2' => 'true if n1 > n2',
          'n1 -ge n2' => 'true if n1 >= n2'
        }
      },
      '[' => {
        synopsis: '[ expr ]',
        description: 'Evaluate conditional expression. Same as test, but requires closing ].'
      },
      'break' => {
        synopsis: 'break [n]',
        description: 'Exit from within a for, while, or until loop. If n is specified, break n levels.'
      },
      'continue' => {
        synopsis: 'continue [n]',
        description: 'Resume the next iteration of the enclosing for, while, or until loop.'
      },
      'pushd' => {
        synopsis: 'pushd [dir | +N | -N]',
        description: 'Save current directory on stack and change to dir.',
        options: {
          '+N' => 'rotate stack, bringing Nth directory to top',
          '-N' => 'rotate stack, bringing Nth directory from bottom to top'
        }
      },
      'popd' => {
        synopsis: 'popd [+N | -N]',
        description: 'Remove entries from the directory stack.',
        options: {
          '+N' => 'remove Nth entry from top of stack',
          '-N' => 'remove Nth entry from bottom of stack'
        }
      },
      'dirs' => {
        synopsis: 'dirs [-c] [-l] [-p] [-v]',
        description: 'Display the directory stack.',
        options: {
          '-c' => 'clear the directory stack',
          '-l' => 'use full pathnames (no ~ substitution)',
          '-p' => 'print one entry per line',
          '-v' => 'print with index numbers'
        }
      },
      'trap' => {
        synopsis: 'trap [-lp] [[arg] signal_spec ...]',
        description: 'Set or display signal handlers.',
        options: {
          '-l' => 'list signal names and numbers',
          '-p' => 'display current trap settings'
        }
      },
      'getopts' => {
        synopsis: 'getopts optstring name [args]',
        description: 'Parse positional parameters as options. Sets OPTIND and OPTARG.'
      },
      'local' => {
        synopsis: 'local [name[=value] ...]',
        description: 'Create local variables within a function. Only valid inside a function.'
      },
      'unset' => {
        synopsis: 'unset [-v] [-f] [name ...]',
        description: 'Unset values and attributes of variables and functions.',
        options: {
          '-v' => 'unset variables (default)',
          '-f' => 'unset functions'
        }
      },
      'readonly' => {
        synopsis: 'readonly [-p] [name[=value] ...]',
        description: 'Mark variables as read-only.',
        options: {
          '-p' => 'display all readonly variables'
        }
      },
      'declare' => {
        synopsis: 'declare [-aAfFgilnprtux] [-p] [name[=value] ...]',
        description: 'Declare variables and give them attributes.',
        options: {
          '-a' => 'indexed array',
          '-A' => 'associative array',
          '-i' => 'integer attribute',
          '-l' => 'convert value to lowercase',
          '-u' => 'convert value to uppercase',
          '-r' => 'make readonly',
          '-x' => 'export to environment',
          '-p' => 'display attributes and values'
        }
      },
      'typeset' => {
        synopsis: 'typeset [-aAfFgilnprtux] [-p] [name[=value] ...]',
        description: 'Declare variables and give them attributes. Same as declare.'
      },
      'let' => {
        synopsis: 'let arg [arg ...]',
        description: 'Evaluate arithmetic expressions. Each arg is an arithmetic expression.'
      },
      'printf' => {
        synopsis: 'printf format [arguments]',
        description: 'Write formatted output. Format specifiers: %s (string), %d (integer), %f (float), etc.'
      },
      'type' => {
        synopsis: 'type [-t|-p|-a] name [name ...]',
        description: 'Display information about command type.',
        options: {
          '-t' => 'print single word: alias, keyword, function, builtin, or file',
          '-p' => 'print disk file path',
          '-a' => 'print all locations'
        }
      },
      'which' => {
        synopsis: 'which [-a] name [name ...]',
        description: 'Locate a command in PATH.',
        options: {
          '-a' => 'print all matching pathnames'
        }
      },
      'true' => {
        synopsis: 'true',
        description: 'Return a successful result (exit status 0).'
      },
      'false' => {
        synopsis: 'false',
        description: 'Return an unsuccessful result (exit status 1).'
      },
      ':' => {
        synopsis: ':',
        description: 'Null command. Does nothing, returns success.'
      },
      'eval' => {
        synopsis: 'eval [arg ...]',
        description: 'Concatenate arguments and execute as a shell command.'
      },
      'command' => {
        synopsis: 'command [-pVv] command [arg ...]',
        description: 'Execute command bypassing shell functions.',
        options: {
          '-p' => 'use default PATH for command search',
          '-v' => 'print command description',
          '-V' => 'print verbose command description'
        }
      },
      'builtin' => {
        synopsis: 'builtin shell-builtin [arguments]',
        description: 'Execute a shell builtin, bypassing functions and aliases.'
      },
      'wait' => {
        synopsis: 'wait [-n] [id ...]',
        description: 'Wait for job completion and return exit status.',
        options: {
          '-n' => 'wait for any single job to complete'
        }
      },
      'kill' => {
        synopsis: 'kill [-s sigspec | -n signum | -sigspec] pid | jobspec ...',
        description: 'Send a signal to a job or process.',
        options: {
          '-l' => 'list signal names',
          '-s sigspec' => 'specify signal by name',
          '-n signum' => 'specify signal by number'
        }
      },
      'umask' => {
        synopsis: 'umask [-p] [-S] [mode]',
        description: 'Display or set file mode creation mask.',
        options: {
          '-p' => 'output in form that may be reused as input',
          '-S' => 'use symbolic output (u=rwx,g=rx,o=rx)'
        }
      },
      'exec' => {
        synopsis: 'exec [-cl] [-a name] [command [arguments ...]]',
        description: 'Replace the shell with command. With no command, redirections affect current shell.',
        options: {
          '-c' => 'execute with empty environment',
          '-l' => 'place dash in argv[0] (login shell)',
          '-a name' => 'set argv[0] to name'
        }
      },
      'times' => {
        synopsis: 'times',
        description: 'Print accumulated user and system times for the shell and its children.'
      },
      'hash' => {
        synopsis: 'hash [-lr] [-p filename] [-dt] [name ...]',
        description: 'Remember or report command locations.',
        options: {
          '-r' => 'forget all remembered locations',
          '-l' => 'display in reusable format',
          '-p filename' => 'use filename as location for name',
          '-d' => 'forget remembered location for name',
          '-t' => 'print location for name'
        }
      },
      'disown' => {
        synopsis: 'disown [-h] [-ar] [jobspec ...]',
        description: 'Remove jobs from the job table.',
        options: {
          '-h' => 'mark jobs so they do not receive SIGHUP',
          '-a' => 'remove all jobs',
          '-r' => 'remove only running jobs'
        }
      },
      'ulimit' => {
        synopsis: 'ulimit [-SHa] [-bcdefiklmnpqrstuvxT] [limit]',
        description: 'Control process resource limits.',
        options: {
          '-S' => 'use soft limit',
          '-H' => 'use hard limit',
          '-a' => 'all current limits are reported',
          '-c' => 'core file size',
          '-d' => 'data segment size',
          '-f' => 'file size',
          '-l' => 'locked memory size',
          '-m' => 'resident set size',
          '-n' => 'open file descriptors',
          '-s' => 'stack size',
          '-t' => 'CPU time',
          '-u' => 'user processes',
          '-v' => 'virtual memory'
        }
      },
      'suspend' => {
        synopsis: 'suspend [-f]',
        description: 'Suspend shell execution.',
        options: {
          '-f' => 'force suspend even if this is a login shell'
        }
      },
      'shopt' => {
        synopsis: 'shopt [-pqsu] [-o] [optname ...]',
        description: 'Set and unset shell options.',
        options: {
          '-s' => 'enable (set) each optname',
          '-u' => 'disable (unset) each optname',
          '-p' => 'display in reusable format',
          '-q' => 'quiet mode, return status indicates if set',
          '-o' => 'restrict optnames to those defined for set -o'
        }
      },
      'enable' => {
        synopsis: 'enable [-a] [-dnps] [-f filename] [name ...]',
        description: 'Enable and disable shell builtins.',
        options: {
          '-a' => 'print all builtins with enabled/disabled status',
          '-n' => 'disable builtin names',
          '-p' => 'print enabled builtins',
          '-s' => 'print only special builtins'
        }
      },
      'caller' => {
        synopsis: 'caller [expr]',
        description: 'Return the context of the current subroutine call. With expr, return the nth entry from the call stack.'
      },
      'complete' => {
        synopsis: 'complete [-abcdefgjksuv] [-pr] [-DEI] [-o comp-option] [-A action] [-G globpat] [-W wordlist] [-F function] [-C command] [-X filterpat] [-P prefix] [-S suffix] [name ...]',
        description: 'Specify how arguments are to be completed.',
        options: {
          '-p' => 'print completion specifications',
          '-r' => 'remove completion specifications',
          '-f' => 'complete with filenames',
          '-d' => 'complete with directories',
          '-b' => 'complete with builtins',
          '-a' => 'complete with aliases',
          '-v' => 'complete with variables',
          '-W wordlist' => 'split wordlist and complete with results',
          '-F function' => 'call function for completions'
        }
      },
      'compgen' => {
        synopsis: 'compgen [-abcdefgjksuv] [-o option] [-A action] [-G globpat] [-W wordlist] [-F function] [-C command] [-X filterpat] [-P prefix] [-S suffix] [word]',
        description: 'Generate possible completions matching word.',
        options: {
          '-b' => 'builtins',
          '-a' => 'aliases',
          '-f' => 'filenames',
          '-d' => 'directories',
          '-v' => 'variables',
          '-W wordlist' => 'words from wordlist',
          '-P prefix' => 'add prefix to each completion',
          '-S suffix' => 'add suffix to each completion'
        }
      },
      'compopt' => {
        synopsis: 'compopt [-o option] [-DE] [+o option] [name ...]',
        description: 'Modify completion options for the currently executing completion, or for named commands.',
        options: {
          '-o option' => 'enable completion option',
          '+o option' => 'disable completion option',
          '-D' => 'apply to default completion',
          '-E' => 'apply to empty command completion',
          'bashdefault' => 'perform bash default completions if no matches',
          'default' => 'use readline default filename completion',
          'dirnames' => 'perform directory name completion',
          'filenames' => 'tell readline completions are filenames',
          'noquote' => 'do not quote completions',
          'nosort' => 'do not sort completions alphabetically',
          'nospace' => 'do not append space after completion',
          'plusdirs' => 'add directory names to generated matches'
        }
      },
      'bind' => {
        synopsis: 'bind [-m keymap] [-lpsvPSVX] [-f filename] [-q name] [-u name] [-r keyseq] [-x keyseq:shell-command] [keyseq:readline-function or keyseq:"macro"]',
        description: 'Set or display readline key bindings and variables.',
        options: {
          '-l' => 'list readline function names',
          '-p' => 'print key bindings',
          '-P' => 'print key bindings with descriptions',
          '-s' => 'print macro bindings',
          '-S' => 'print macro bindings with descriptions',
          '-v' => 'print readline variables',
          '-V' => 'print readline variables with descriptions',
          '-X' => 'print shell command bindings',
          '-q name' => 'query which keys invoke named function',
          '-u name' => 'unbind all keys bound to named function',
          '-r keyseq' => 'remove binding for keyseq',
          '-f filename' => 'read bindings from filename',
          '-x keyseq:cmd' => 'bind keyseq to shell command',
          '-m keymap' => 'use keymap for subsequent bindings'
        }
      },
      'help' => {
        synopsis: 'help [-dms] [pattern ...]',
        description: 'Display information about builtin commands.',
        options: {
          '-d' => 'output short description for each topic',
          '-m' => 'display in pseudo-manpage format',
          '-s' => 'output only a short usage synopsis'
        }
      },
      'fc' => {
        synopsis: 'fc [-e ename] [-lnr] [first] [last] or fc -s [pat=rep] [command]',
        description: 'Display or edit and re-execute commands from the history list.',
        options: {
          '-e ename' => 'use ename as the editor (default: $FCEDIT or $EDITOR or vi)',
          '-l' => 'list commands instead of editing',
          '-n' => 'suppress line numbers when listing',
          '-r' => 'reverse the order of the commands',
          '-s' => 're-execute command without invoking editor'
        }
      },
      'mapfile' => {
        synopsis: 'mapfile [-d delim] [-n count] [-O origin] [-s count] [-t] [-u fd] [-C callback] [-c quantum] [array]',
        description: 'Read lines from standard input into an indexed array variable.',
        options: {
          '-d delim' => 'use delim as line delimiter instead of newline',
          '-n count' => 'read at most count lines (0 means all)',
          '-O origin' => 'begin assigning at index origin (default 0)',
          '-s count' => 'skip the first count lines',
          '-t' => 'remove trailing delimiter from each line',
          '-u fd' => 'read from file descriptor fd instead of stdin',
          '-C callback' => 'evaluate callback each time quantum lines are read',
          '-c quantum' => 'specify the number of lines between callback calls (default 5000)'
        }
      },
      'readarray' => {
        synopsis: 'readarray [-d delim] [-n count] [-O origin] [-s count] [-t] [-u fd] [-C callback] [-c quantum] [array]',
        description: 'Read lines from standard input into an indexed array variable. Synonym for mapfile.'
      }
    }.freeze

    def self.run_help(args)
      # Parse options
      short_desc = false
      manpage = false
      synopsis_only = false

      while args.first&.start_with?('-')
        opt = args.shift
        case opt
        when '-d'
          short_desc = true
        when '-m'
          manpage = true
        when '-s'
          synopsis_only = true
        else
          puts "help: #{opt}: invalid option"
          puts 'help: usage: help [-dms] [pattern ...]'
          return false
        end
      end

      if args.empty?
        # No pattern: list all builtins with short descriptions
        print_all_builtins(short_desc)
        return true
      end

      found_any = false
      args.each do |pattern|
        # Find matching builtins (exact match first, then glob patterns)
        matches = if COMMANDS.include?(pattern)
                    [pattern]
                  else
                    COMMANDS.select { |cmd| File.fnmatch(pattern, cmd) }
                  end

        if matches.empty?
          puts "help: no help topics match '#{pattern}'."
        else
          matches.each do |cmd|
            found_any = true
            print_help_for(cmd, short_desc: short_desc, manpage: manpage, synopsis_only: synopsis_only)
          end
        end
      end

      found_any
    end

    def self.print_all_builtins(short_desc)
      puts 'Shell builtin commands:'
      puts

      if short_desc
        # Print each builtin with short description
        COMMANDS.sort.each do |cmd|
          info = BUILTIN_HELP[cmd]
          if info
            puts "#{cmd} - #{info[:description].split('.').first}."
          else
            puts cmd
          end
        end
      else
        # Print in columns
        builtins = COMMANDS.sort
        col_width = builtins.map(&:length).max + 2
        cols = 80 / col_width
        cols = 1 if cols < 1

        builtins.each_slice(cols) do |row|
          puts row.map { |b| b.ljust(col_width) }.join
        end
      end
    end

    def self.print_help_for(cmd, short_desc: false, manpage: false, synopsis_only: false)
      info = BUILTIN_HELP[cmd]

      unless info
        puts "#{cmd}: no help available"
        return
      end

      if synopsis_only
        puts "#{cmd}: #{info[:synopsis]}"
        return
      end

      if short_desc
        puts "#{cmd} - #{info[:description].split('.').first}."
        return
      end

      if manpage
        print_manpage_format(cmd, info)
      else
        print_standard_format(cmd, info)
      end
    end

    def self.print_standard_format(cmd, info)
      puts "#{cmd}: #{info[:synopsis]}"
      puts "    #{info[:description]}"

      if info[:options] && !info[:options].empty?
        puts
        puts '    Options:'
        info[:options].each do |opt, desc|
          puts "      #{opt.ljust(16)} #{desc}"
        end
      end
      puts
    end

    def self.print_manpage_format(cmd, info)
      puts 'NAME'
      short_desc = info[:description].split('.').first
      puts "    #{cmd} - #{short_desc.downcase}"
      puts
      puts 'SYNOPSIS'
      puts "    #{info[:synopsis]}"
      puts
      puts 'DESCRIPTION'
      # Wrap description at ~70 chars
      desc_lines = wrap_text(info[:description], 66)
      desc_lines.each { |line| puts "    #{line}" }

      if info[:options] && !info[:options].empty?
        puts
        puts 'OPTIONS'
        info[:options].each do |opt, desc|
          puts "    #{opt}"
          wrapped = wrap_text(desc, 62)
          wrapped.each { |line| puts "        #{line}" }
        end
      end
      puts
    end

    def self.wrap_text(text, width)
      return [text] if text.length <= width

      lines = []
      current = +''
      text.split.each do |word|
        if current.empty?
          current = word
        elsif current.length + word.length + 1 <= width
          current << ' ' << word
        else
          lines << current
          current = word
        end
      end
      lines << current unless current.empty?
      lines
    end

    def self.run_fc(args)
      # Parse options
      list_mode = false
      suppress_numbers = false
      reverse_order = false
      reexecute_mode = false
      editor = nil

      while args.first&.start_with?('-') && args.first != '-' && args.first !~ /\A-\d+\z/
        opt = args.shift
        case opt
        when '-l'
          list_mode = true
        when '-n'
          suppress_numbers = true
        when '-r'
          reverse_order = true
        when '-s'
          reexecute_mode = true
        when '-e'
          editor = args.shift
          unless editor
            puts 'fc: -e: option requires an argument'
            return false
          end
        when /\A-[lnr]+\z/
          # Combined flags like -ln, -lr, -lnr
          opt.chars[1..].each do |c|
            case c
            when 'l' then list_mode = true
            when 'n' then suppress_numbers = true
            when 'r' then reverse_order = true
            end
          end
        else
          puts "fc: #{opt}: invalid option"
          puts 'fc: usage: fc [-e ename] [-lnr] [first] [last] or fc -s [pat=rep] [command]'
          return false
        end
      end

      history = Reline::HISTORY.to_a
      return true if history.empty?

      # Handle -s (re-execute) mode
      if reexecute_mode
        return fc_reexecute(args, history)
      end

      # Parse first and last arguments
      first_arg = args.shift
      last_arg = args.shift

      # Resolve range
      first_idx, last_idx = fc_resolve_range(first_arg, last_arg, history, list_mode)
      return false unless first_idx

      # Get commands in range
      commands = fc_get_range(history, first_idx, last_idx)
      commands.reverse! if reverse_order

      if list_mode
        # List mode: display commands
        fc_list_commands(commands, first_idx, last_idx, reverse_order, suppress_numbers)
        true
      else
        # Edit mode: edit and execute commands
        fc_edit_and_execute(commands, editor)
      end
    end

    def self.fc_reexecute(args, history)
      # fc -s [pat=rep] [command]
      substitution = nil
      command_spec = nil

      args.each do |arg|
        if arg.include?('=') && substitution.nil?
          substitution = arg
        else
          command_spec = arg
        end
      end

      # Find the command to re-execute
      cmd = if command_spec.nil?
              history.last
            elsif command_spec =~ /\A-?\d+\z/
              idx = command_spec.to_i
              if idx < 0
                history[idx]
              else
                history[idx - 1]
              end
            else
              # Find command starting with string
              history.reverse.find { |c| c.start_with?(command_spec) }
            end

      unless cmd
        puts 'fc: no command found'
        return false
      end

      # Apply substitution if specified
      if substitution
        pat, rep = substitution.split('=', 2)
        cmd = cmd.sub(pat, rep || '')
      end

      # Display and execute the command
      puts cmd
      @executor&.call(cmd) if @executor
      true
    end

    def self.fc_resolve_range(first_arg, last_arg, history, list_mode)
      hist_size = history.size

      # Default range for list mode: last 16 commands
      # Default range for edit mode: last command
      if first_arg.nil?
        if list_mode
          first_idx = [hist_size - 16, 0].max
          last_idx = hist_size - 1
        else
          first_idx = hist_size - 1
          last_idx = hist_size - 1
        end
        return [first_idx, last_idx]
      end

      # Parse first argument
      first_idx = fc_parse_history_ref(first_arg, history)
      unless first_idx
        puts "fc: #{first_arg}: history specification out of range"
        return nil
      end

      # Parse last argument (defaults to first in list mode, or first in edit mode)
      if last_arg.nil?
        last_idx = list_mode ? hist_size - 1 : first_idx
      else
        last_idx = fc_parse_history_ref(last_arg, history)
        unless last_idx
          puts "fc: #{last_arg}: history specification out of range"
          return nil
        end
      end

      [first_idx, last_idx]
    end

    def self.fc_parse_history_ref(ref, history)
      hist_size = history.size

      if ref =~ /\A-?\d+\z/
        n = ref.to_i
        if n < 0
          # Negative: relative to end
          idx = hist_size + n
        elsif n == 0
          idx = hist_size - 1
        else
          # Positive: absolute (1-based)
          idx = n - 1
        end
        return nil if idx < 0 || idx >= hist_size
        idx
      else
        # String: find most recent command starting with string
        idx = history.rindex { |cmd| cmd.start_with?(ref) }
        idx
      end
    end

    def self.fc_get_range(history, first_idx, last_idx)
      if first_idx <= last_idx
        (first_idx..last_idx).map { |i| [i + 1, history[i]] }
      else
        (last_idx..first_idx).map { |i| [i + 1, history[i]] }.reverse
      end
    end

    def self.fc_list_commands(commands, first_idx, last_idx, reverse_order, suppress_numbers)
      commands.each do |num, cmd|
        if suppress_numbers
          puts cmd
        else
          puts format('%5d  %s', num, cmd)
        end
      end
    end

    def self.fc_edit_and_execute(commands, editor)
      # Determine editor
      editor ||= ENV['FCEDIT'] || ENV['EDITOR'] || 'vi'

      # Create temp file with commands
      tempfile = Tempfile.new(['fc', '.sh'])
      begin
        commands.each { |_num, cmd| tempfile.puts cmd }
        tempfile.close

        # Open editor
        system(editor, tempfile.path)

        # Read edited commands
        edited = File.read(tempfile.path)

        # Execute each line
        edited.each_line do |line|
          line = line.chomp
          next if line.empty? || line.start_with?('#')
          puts line
          @executor&.call(line) if @executor
        end

        true
      ensure
        tempfile.unlink
      end
    end

    def self.run_mapfile(args)
      # Parse options
      delimiter = "\n"
      max_count = 0  # 0 means unlimited
      origin = 0
      skip_count = 0
      strip_trailing = false
      fd = nil
      callback = nil
      quantum = 5000
      array_name = 'MAPFILE'

      while args.first&.start_with?('-')
        opt = args.shift
        case opt
        when '-d'
          delimiter = args.shift
          unless delimiter
            puts 'mapfile: -d: option requires an argument'
            return false
          end
          # Handle escape sequences
          delimiter = delimiter.gsub('\n', "\n").gsub('\t', "\t").gsub('\0', "\0")
        when '-n'
          count_str = args.shift
          unless count_str
            puts 'mapfile: -n: option requires an argument'
            return false
          end
          max_count = count_str.to_i
        when '-O'
          origin_str = args.shift
          unless origin_str
            puts 'mapfile: -O: option requires an argument'
            return false
          end
          origin = origin_str.to_i
        when '-s'
          skip_str = args.shift
          unless skip_str
            puts 'mapfile: -s: option requires an argument'
            return false
          end
          skip_count = skip_str.to_i
        when '-t'
          strip_trailing = true
        when '-u'
          fd_str = args.shift
          unless fd_str
            puts 'mapfile: -u: option requires an argument'
            return false
          end
          fd = fd_str.to_i
        when '-C'
          callback = args.shift
          unless callback
            puts 'mapfile: -C: option requires an argument'
            return false
          end
        when '-c'
          quantum_str = args.shift
          unless quantum_str
            puts 'mapfile: -c: option requires an argument'
            return false
          end
          quantum = quantum_str.to_i
        else
          puts "mapfile: #{opt}: invalid option"
          puts 'mapfile: usage: mapfile [-d delim] [-n count] [-O origin] [-s count] [-t] [-u fd] [-C callback] [-c quantum] [array]'
          return false
        end
      end

      # Get array name if provided
      array_name = args.shift if args.first

      # Read input
      input = if fd
                begin
                  IO.new(fd).read
                rescue Errno::EBADF
                  puts "mapfile: #{fd}: invalid file descriptor"
                  return false
                end
              else
                $stdin.read
              end

      return true if input.nil? || input.empty?

      # Split into lines using delimiter
      lines = if delimiter == "\n"
                input.lines(chomp: false)
              else
                input.split(delimiter, -1).map { |l| "#{l}#{delimiter}" }
              end

      # Remove the last empty element if input ended with delimiter
      lines.pop if lines.last == delimiter || lines.last&.empty?

      # Skip first N lines
      lines = lines.drop(skip_count) if skip_count > 0

      # Limit to max_count lines
      lines = lines.take(max_count) if max_count > 0

      # Clear existing array elements (from origin onwards)
      ENV.keys.select { |k| k.start_with?("#{array_name}_") }.each do |k|
        idx = k.sub("#{array_name}_", '').to_i
        ENV.delete(k) if idx >= origin
      end

      # Store lines in array
      lines.each_with_index do |line, i|
        # Strip trailing delimiter if -t was used
        line = line.chomp(delimiter) if strip_trailing

        idx = origin + i
        ENV["#{array_name}_#{idx}"] = line

        # Call callback if specified
        if callback && ((i + 1) % quantum == 0)
          @executor&.call("#{callback} #{idx} #{line.inspect}")
        end
      end

      # Set array length marker
      ENV["#{array_name}_LENGTH"] = lines.length.to_s

      true
    end

    # Helper to get mapfile array contents
    def self.get_mapfile_array(name = 'MAPFILE')
      length = ENV["#{name}_LENGTH"]&.to_i || 0
      (0...length).map { |i| ENV["#{name}_#{i}"] }
    end

    # Helper to clear mapfile array
    def self.clear_mapfile_array(name = 'MAPFILE')
      ENV.keys.select { |k| k.start_with?("#{name}_") }.each { |k| ENV.delete(k) }
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
