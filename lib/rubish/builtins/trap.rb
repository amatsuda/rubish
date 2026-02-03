# frozen_string_literal: true

module Rubish
  module Builtins
    # Signal name mapping
    # Map signal names/numbers to canonical signal names
    # Includes both short names (HUP) and long names (SIGHUP)
    SIGNALS = {
      # Pseudo-signals (shell-specific, not OS signals)
      'EXIT' => 0,
      'ERR' => 'ERR',        # Triggered on command failure
      'DEBUG' => 'DEBUG',    # Triggered before each command
      'RETURN' => 'RETURN',  # Triggered when function/sourced script returns

      # Standard signals with numeric mappings
      '0' => 0,              # EXIT
      '1' => 'HUP',  'HUP' => 'HUP',   'SIGHUP' => 'HUP',
      '2' => 'INT',  'INT' => 'INT',   'SIGINT' => 'INT',
      '3' => 'QUIT', 'QUIT' => 'QUIT', 'SIGQUIT' => 'QUIT',
      '4' => 'ILL',  'ILL' => 'ILL',   'SIGILL' => 'ILL',
      '5' => 'TRAP', 'TRAP' => 'TRAP', 'SIGTRAP' => 'TRAP',
      '6' => 'ABRT', 'ABRT' => 'ABRT', 'SIGABRT' => 'ABRT', 'IOT' => 'ABRT', 'SIGIOT' => 'ABRT',
      '7' => 'EMT',  'EMT' => 'EMT',   'SIGEMT' => 'EMT',
      '8' => 'FPE',  'FPE' => 'FPE',   'SIGFPE' => 'FPE',
      '9' => 'KILL', 'KILL' => 'KILL', 'SIGKILL' => 'KILL',
      '10' => 'BUS', 'BUS' => 'BUS',   'SIGBUS' => 'BUS',
      '11' => 'SEGV', 'SEGV' => 'SEGV', 'SIGSEGV' => 'SEGV',
      '12' => 'SYS', 'SYS' => 'SYS',   'SIGSYS' => 'SYS',
      '13' => 'PIPE', 'PIPE' => 'PIPE', 'SIGPIPE' => 'PIPE',
      '14' => 'ALRM', 'ALRM' => 'ALRM', 'SIGALRM' => 'ALRM',
      '15' => 'TERM', 'TERM' => 'TERM', 'SIGTERM' => 'TERM',
      '16' => 'URG', 'URG' => 'URG',   'SIGURG' => 'URG',
      '17' => 'STOP', 'STOP' => 'STOP', 'SIGSTOP' => 'STOP',
      '18' => 'TSTP', 'TSTP' => 'TSTP', 'SIGTSTP' => 'TSTP',
      '19' => 'CONT', 'CONT' => 'CONT', 'SIGCONT' => 'CONT',
      '20' => 'CHLD', 'CHLD' => 'CHLD', 'SIGCHLD' => 'CHLD', 'CLD' => 'CHLD', 'SIGCLD' => 'CHLD',
      '21' => 'TTIN', 'TTIN' => 'TTIN', 'SIGTTIN' => 'TTIN',
      '22' => 'TTOU', 'TTOU' => 'TTOU', 'SIGTTOU' => 'TTOU',
      '23' => 'IO',   'IO' => 'IO',     'SIGIO' => 'IO', 'POLL' => 'IO', 'SIGPOLL' => 'IO',
      '24' => 'XCPU', 'XCPU' => 'XCPU', 'SIGXCPU' => 'XCPU',
      '25' => 'XFSZ', 'XFSZ' => 'XFSZ', 'SIGXFSZ' => 'XFSZ',
      '26' => 'VTALRM', 'VTALRM' => 'VTALRM', 'SIGVTALRM' => 'VTALRM',
      '27' => 'PROF', 'PROF' => 'PROF', 'SIGPROF' => 'PROF',
      '28' => 'WINCH', 'WINCH' => 'WINCH', 'SIGWINCH' => 'WINCH',
      '29' => 'INFO', 'INFO' => 'INFO', 'SIGINFO' => 'INFO',
      '30' => 'USR1', 'USR1' => 'USR1', 'SIGUSR1' => 'USR1',
      '31' => 'USR2', 'USR2' => 'USR2', 'SIGUSR2' => 'USR2'
    }.freeze

    # Signals that cannot be trapped (for error messages)
    UNTRAPABLE_SIGNALS = %w[KILL STOP].freeze

    def trap(args)
      if args.empty?
        # List all traps
        @state.traps.each do |sig, cmd|
          sig_name = signal_display_name(sig)
          puts "trap -- #{cmd.inspect} #{sig_name}"
        end
        return true
      end

      # trap -l: list signal names (bash-style format)
      if args.first == '-l'
        # Get unique signals sorted by number, format like bash: " 1) HUP  2) INT ..."
        signals = Signal.list.reject { |k, _| k == 'EXIT' }  # EXIT is 0, handled specially
        by_num = signals.group_by { |_, v| v }.transform_values { |pairs| pairs.map(&:first).min }
        sorted = by_num.sort_by { |num, _| num }

        # Print in columns like bash
        col = 0
        sorted.each do |num, name|
          print format('%2d) %-8s', num, name)
          col += 1
          if col >= 5
            puts
            col = 0
          end
        end
        puts if col > 0
        return true
      end

      # trap -p [signal...]: print trap commands
      if args.first == '-p'
        signals = args[1..] || []
        if signals.empty?
          @state.traps.each do |sig, cmd|
            sig_name = signal_display_name(sig)
            puts "trap -- #{cmd.inspect} #{sig_name}"
          end
        else
          signals.each do |sig_arg|
            sig = normalize_signal(sig_arg)
            next unless sig

            if @state.traps.key?(sig)
              sig_name = signal_display_name(sig)
              puts "trap -- #{@state.traps[sig].inspect} #{sig_name}"
            end
          end
        end
        return true
      end

      # trap command signal [signal...]
      # trap '' signal - ignore signal
      # trap - signal - reset to default
      # trap -- command signal - use -- to separate options from command
      # Skip -- if present (end of options marker)
      if args.first == '--'
        args = args[1..]
      end
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
        elsif command.empty?
          # Ignore signal
          set_trap(sig, '')
        else
          # Set trap
          set_trap(sig, command)
        end
      end

      true
    end

    # Pseudo-signals that are not real OS signals
    PSEUDO_SIGNALS = [0, 'ERR', 'DEBUG', 'RETURN'].freeze

    def set_trap(sig, command)
      # KILL and STOP cannot be trapped or ignored
      sig_name = sig.is_a?(Integer) ? nil : sig.to_s.upcase
      if UNTRAPABLE_SIGNALS.include?(sig_name)
        puts "trap: #{sig_name}: cannot be trapped"
        return false
      end

      # Store the trap command
      @state.traps[sig] = command

      # Pseudo-signals are handled by the shell, not the OS
      return true if PSEUDO_SIGNALS.include?(sig)

      # Save original handler if not already saved
      @state.original_traps[sig] ||= Signal.trap(sig, 'DEFAULT') rescue nil

      if command.empty?
        # Ignore the signal
        Signal.trap(sig, 'IGNORE')
      else
        # Set up the handler
        # Capture signal name for RUBISH_TRAPSIG/BASH_TRAPSIG
        sig_name = sig.is_a?(Integer) ? Signal.signame(sig) : sig.to_s.sub(/^SIG/, '')
        Signal.trap(sig) do
          @state.current_trapsig = sig_name
          begin
            @state.executor&.call(command) if @state.executor
          ensure
            @state.current_trapsig = ''
          end
        end
      end
      true
    rescue ArgumentError => e
      puts "trap: #{e.message}"
      false
    end

    def reset_trap(sig)
      @state.traps.delete(sig)

      # Pseudo-signals have no OS signal to reset
      return if PSEUDO_SIGNALS.include?(sig)

      # Restore original handler
      if @state.original_traps.key?(sig)
        Signal.trap(sig, @state.original_traps.delete(sig) || 'DEFAULT')
      else
        Signal.trap(sig, 'DEFAULT')
      end
    rescue ArgumentError => e
      puts "trap: #{e.message}"
    end

    def exit_traps
      return unless @state.traps.key?(0)

      @state.current_trapsig = 'EXIT'
      begin
        @state.executor&.call(@state.traps[0]) if @state.executor
      ensure
        @state.current_trapsig = ''
      end
    end

    def err_trap
      return unless @state.traps.key?('ERR')
      return if @in_err_trap  # Prevent recursion

      @in_err_trap = true
      @state.current_trapsig = 'ERR'
      begin
        @state.executor&.call(@state.traps['ERR']) if @state.executor
      ensure
        @in_err_trap = false
        @state.current_trapsig = ''
      end
    end

    def err_trap_set?
      @state.traps.key?('ERR') && !@state.traps['ERR'].empty?
    end

    def save_and_clear_err_trap
      # Save ERR trap and clear it (for functions/subshells when errtrace is off)
      saved = @state.traps.delete('ERR')
      saved
    end

    def restore_err_trap(saved)
      # Restore a previously saved ERR trap
      if saved
        @state.traps['ERR'] = saved
      end
    end

    def debug_trap
      return unless @state.traps.key?('DEBUG')
      return if @in_debug_trap  # Prevent recursion

      @in_debug_trap = true
      @state.current_trapsig = 'DEBUG'
      begin
        @state.executor&.call(@state.traps['DEBUG']) if @state.executor
      ensure
        @in_debug_trap = false
        @state.current_trapsig = ''
      end
    end

    def debug_trap_set?
      @state.traps.key?('DEBUG') && !@state.traps['DEBUG'].empty?
    end

    def return_trap
      return unless @state.traps.key?('RETURN')
      return if @in_return_trap  # Prevent recursion

      @in_return_trap = true
      @state.current_trapsig = 'RETURN'
      begin
        @state.executor&.call(@state.traps['RETURN']) if @state.executor
      ensure
        @in_return_trap = false
        @state.current_trapsig = ''
      end
    end

    def return_trap_set?
      @state.traps.key?('RETURN') && !@state.traps['RETURN'].empty?
    end

    def save_and_clear_functrace_traps
      # Save DEBUG and RETURN traps and clear them (for functions when functrace is off)
      saved = {}
      saved['DEBUG'] = @state.traps.delete('DEBUG') if @state.traps.key?('DEBUG')
      saved['RETURN'] = @state.traps.delete('RETURN') if @state.traps.key?('RETURN')
      saved.empty? ? nil : saved
    end

    def restore_functrace_traps(saved)
      # Restore previously saved DEBUG and RETURN traps
      return unless saved

      @state.traps['DEBUG'] = saved['DEBUG'] if saved['DEBUG']
      @state.traps['RETURN'] = saved['RETURN'] if saved['RETURN']
    end

    def clear_traps
      @state.traps.each_key do |sig|
        reset_trap(sig) unless PSEUDO_SIGNALS.include?(sig)
      end
      @state.traps.clear
      @state.original_traps.clear
    end

    def normalize_signal(sig_arg)
      sig_str = sig_arg.to_s

      # Look up in SIGNALS hash (handles both numeric and named signals)
      sig_upper = sig_str.upcase
      result = SIGNALS[sig_upper]
      return result if result

      # For pure numeric input not in SIGNALS, return as integer
      return sig_str.to_i if sig_str =~ /\A\d+\z/

      nil
    end

    private

    def signal_display_name(sig)
      sig == 0 ? 'EXIT' : sig
    end
  end
end
