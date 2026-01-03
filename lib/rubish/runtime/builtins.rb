# frozen_string_literal: true

module Rubish
  module Builtins
    COMMANDS = %w(cd exit jobs fg bg export pwd history alias unalias source . shift set return read echo test [ break continue pushd popd dirs trap getopts local unset readonly declare typeset let printf type).freeze

    @aliases = {}
    @dir_stack = []
    @traps = {}
    @original_traps = {}
    @local_scope_stack = []  # Stack of hashes for local variable scopes
    @readonly_vars = {}  # Hash of readonly variable names to their values
    @var_attributes = {}  # Hash of variable names to Set of attributes (:integer, :lowercase, :uppercase, :export)
    @executor = nil
    @script_name_getter = nil
    @script_name_setter = nil
    @positional_params_getter = nil
    @positional_params_setter = nil
    @function_checker = nil
    @function_remover = nil
    @heredoc_content_setter = nil

    class << self
      attr_reader :aliases, :dir_stack, :traps, :local_scope_stack, :readonly_vars, :var_attributes
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
      when 'declare', 'typeset'
        run_declare(args)
      when 'let'
        run_let(args)
      when 'printf'
        run_printf(args)
      when 'type'
        run_type(args)
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

    def self.run_declare(args)
      # declare [-aAilrux] [-p] [name[=value] ...]
      # -i: integer attribute (arithmetic evaluation)
      # -l: lowercase attribute
      # -u: uppercase attribute
      # -r: readonly attribute
      # -x: export attribute
      # -p: print declarations
      # +attr: remove attribute

      # Parse options
      print_mode = false
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
