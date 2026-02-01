# frozen_string_literal: true

require_relative 'prompt'
require_relative 'completion'
require_relative 'history'
require_relative 'config'
require_relative 'arithmetic'
require_relative 'expansion'
require_relative 'runtime'
require_relative 'shell_state'
require_relative 'execution_context'

module Rubish
  class NounsetError < StandardError; end
  class FailglobError < StandardError; end

  class REPL
    include Prompt
    include Completion
    include History
    include Config
    include Arithmetic
    include Expansion
    include Runtime

    def initialize(login_shell: false, no_profile: false, no_rc: false, restricted: false, rcfile: nil)
      # Create shell state and execution context for this REPL instance
      @state = ShellState.new
      @context = ExecutionContext.new(@state)
      # Set current_state and context for backward compatibility with Builtins.xxx class method calls
      Builtins.current_state = @state
      Builtins.context = @context
      @lexer_class = Lexer
      @parser_class = Parser
      @codegen = Codegen.new
      @last_line = nil
      @last_status = 0
      @last_bg_pid = nil
      @command_number = 1
      @script_name = 'rubish'
      @positional_params = []
      @functions = {}
      @heredoc_content = nil  # Content for current heredoc
      @seconds_base = Time.now  # For SECONDS variable
      @random_generator = Random.new  # For RANDOM variable
      @lineno = 1  # For LINENO variable
      @pipestatus = [0]  # For PIPESTATUS array variable
      @rubish_command = ''  # For RUBISH_COMMAND variable (current command being executed)
      @funcname_stack = []  # For FUNCNAME array variable (function call stack)
      @rubish_lineno_stack = []  # For RUBISH_LINENO array variable (line numbers of function calls)
      @current_source_file = 'main'  # Current source file being executed (for RUBISH_SOURCE)
      @rubish_source_stack = []  # For RUBISH_SOURCE array variable (source files of function calls)
      @rubish_argc_stack = []  # For RUBISH_ARGC array variable (argument counts per call frame)
      @rubish_argv_stack = []  # For RUBISH_ARGV array variable (all arguments in call stack)
      @subshell_level = 0  # For RUBISH_SUBSHELL variable (nesting level of subshells)
      @eof_count = 0  # For IGNOREEOF variable (consecutive EOF counter)
      @last_mail_check = Time.now  # For MAIL/MAILCHECK - last time we checked for mail
      @mail_mtimes = {}  # For MAIL/MAILCHECK - hash of mail file paths to their last known mtime
      @mail_atimes = {}  # For mailwarn - hash of mail file paths to their last known atime
      @varname_fds = {}  # For {varname} redirection - maps varname to allocated FD
      @next_varname_fd = 10  # Next FD to allocate for {varname} redirections
      @bash_argv0_unset = false  # Track if BASH_ARGV0 has been unset (loses special properties)
      @readline_line = ''  # For READLINE_LINE variable (current line buffer in bind -x)
      @readline_point = 0  # For READLINE_POINT variable (cursor position in bind -x)
      @readline_mark = 0   # For READLINE_MARK variable (mark position in bind -x)
      @login_shell = login_shell  # Whether this is a login shell
      @no_profile = no_profile    # Skip profile files (--noprofile)
      @no_rc = no_rc              # Skip rc files (--norc)
      @restricted = restricted    # Start in restricted mode (-r or rbash)
      @rcfile = rcfile            # Custom RC file (--rcfile, --init-file)
      # Set the login_shell shopt option (read-only)
      @context.set_shell_option('login_shell', login_shell)
      # SHLVL - shell nesting level (stored in ENV for inheritance)
      current_shlvl = ENV['SHLVL'].to_i
      ENV['SHLVL'] = (current_shlvl + 1).to_s
      # SHELL - full pathname of the shell
      # Set to the rubish binary path if not already set or if running rubish
      set_shell_variable
      @state.executor = ->(line) { execute(line) }
      @state.script_name_getter = -> { @script_name }
      @state.script_name_setter = ->(name) { @script_name = name }
      @state.positional_params_getter = -> { @positional_params }
      @state.positional_params_setter = ->(params) { @positional_params = params }
      @state.function_checker = ->(name) { @functions.key?(name) }
      @state.function_remover = ->(name) { @functions.delete(name) }
      @state.function_lister = -> { @functions.transform_values { |v| {source: v[:source_code], file: v[:source], lineno: v[:lineno]} } }
      @state.function_getter = ->(name) { f = @functions[name]; f ? {source: f[:source_code], file: f[:source], lineno: f[:lineno]} : nil }
      @state.heredoc_content_setter = ->(content) { @heredoc_content = content }
      @state.command_executor = ->(args) { execute_command_directly(args) }
      @state.source_file_getter = -> { @current_source_file }
      @state.source_file_setter = ->(file) { @current_source_file = file }
      @state.lineno_getter = -> { @lineno }
      @state.bash_argv0_unsetter = -> { @bash_argv0_unset = true }
      # Readline state callbacks
      @state.readline_line_getter = -> { @readline_line }
      @state.readline_line_setter = ->(line) { @readline_line = line }
      @state.readline_point_getter = -> { @readline_point }
      @state.readline_point_setter = ->(point) { @readline_point = point }
      @state.readline_mark_getter = -> { @readline_mark }
      @state.readline_mark_setter = ->(mark) { @readline_mark = mark }
      # bind -x executor: execute shell commands from key bindings
      @state.bind_x_executor = ->(command) { execute_bind_x_command(command) }
      # History callbacks
      @state.history_file_getter = -> { history_file }
      @state.history_loader = -> { load_history }
      @state.history_saver = -> { save_history }
      @state.history_appender = -> { append_history }
      # Set up Command class to handle functions in pipelines
      Command.function_checker = ->(name) { @functions.key?(name) }
      Command.function_caller = ->(name, args) { call_function(name, args) }
      # Set up state to call functions (for compgen -F)
      @state.function_caller = ->(name, args) { call_function(name, args) }
      # Source executor for autoload: source a file or execute code string
      @state.source_executor = ->(file, code = nil) {
        if code
          # Execute code string directly
          execute(code)
        elsif file
          # Source a file
          run_source([file])
        end
      }
    end

    attr_accessor :script_name, :positional_params, :functions, :lineno

    def run
      # Start buffering stdin immediately so typed input during slow startup is preserved
      start_stdin_buffering

      begin
        setup_job_control
        setup_reline
        setup_signals
        setup_terminal_title
        Builtins.notify_terminal_of_cwd
        load_history
        setup_default_aliases
        load_config
        # Enable restricted mode AFTER startup files are sourced
        # This allows profile/rc files to set PATH and other variables
        Builtins.enable_restricted_mode if @restricted
      ensure
        # Stop buffering and inject any typed input into the first prompt
        # This is in ensure block to guarantee terminal is restored even on error
        inject_buffered_input
      end

      exit_code = catch(:exit) do
        loop { process_line }
      end
      save_history
      load_logout_config
      exit_code
    end

    # Buffer stdin input during startup so typed characters aren't lost
    def start_stdin_buffering
      return unless $stdin.tty?

      @stdin_buffer = +''
      @stdin_buffering = true

      # Save original terminal settings
      begin
        @original_termios = `stty -g`.chomp
      rescue
        @original_termios = nil
      end

      # Start a thread to read stdin in non-blocking mode
      @stdin_buffer_thread = Thread.new do
        begin
          # Put terminal in raw mode to capture all keystrokes
          system('stty raw -echo') if @original_termios

          while @stdin_buffering
            # Check if input is available (with short timeout)
            if IO.select([$stdin], nil, nil, 0.05)
              begin
                char = $stdin.read_nonblock(1)
                @stdin_buffer << char if char
              rescue IO::WaitReadable, EOFError
                # No data available or EOF
              end
            end
          end
        rescue => e
          # Silently ignore errors in buffering thread
        ensure
          # Restore terminal settings
          system("stty #{@original_termios}") if @original_termios
        end
      end
    end

    # Stop stdin buffering and inject buffered content into Reline
    def inject_buffered_input
      # Always restore terminal settings first, even if no thread was started
      if @original_termios
        system("stty #{@original_termios}") rescue nil
        @original_termios = nil
      end

      # Stop the buffering thread if it's running
      if @stdin_buffer_thread
        # Signal the thread to stop
        @stdin_buffering = false

        begin
          @stdin_buffer_thread.join(0.2)  # Wait briefly for thread to finish
        rescue
          # Ignore join errors
        end

        begin
          @stdin_buffer_thread.kill if @stdin_buffer_thread.alive?
        rescue
          # Ignore kill errors
        end
        @stdin_buffer_thread = nil
      end

      # If we have buffered input, inject it into the first readline
      return if @stdin_buffer.nil? || @stdin_buffer.empty?

      buffered = @stdin_buffer.dup
      @stdin_buffer = nil

      # Handle special characters in buffered input
      # Remove any carriage returns, keep newlines for multi-command handling
      buffered.gsub!("\r", "\n")

      # If buffer contains newlines, we have complete commands to execute
      if buffered.include?("\n")
        lines = buffered.split("\n", -1)
        # Last element is the incomplete line (could be empty)
        incomplete = lines.pop

        # Execute complete lines immediately after first prompt
        @pending_commands = lines.reject(&:empty?)

        # Set up the incomplete line as initial input
        buffered = incomplete
      end

      # Use pre_input_hook to insert buffered text into first readline
      return if buffered.nil? || buffered.empty?

      Reline.pre_input_hook = -> {
        Reline.insert_text(buffered)
        Reline.pre_input_hook = nil  # Only for first prompt
      }
    end

    private

    def setup_reline
      repl = self

      Reline.completion_proc = ->(input) {
        result = repl.send(:complete, input)
        candidates = result.is_a?(Array) ? result : []
        candidates.map { |c| c.end_with?('/') ? c : "#{c} " }
      }

      # Set up default completions for common commands
      Builtins.setup_default_completions
      # Load inputrc configuration
      # INPUTRC environment variable specifies the inputrc file location
      # Falls back to ~/.inputrc, then ~/.config/readline/inputrc
      load_inputrc
      # Set word break characters AFTER loading inputrc to ensure / is not included
      # This enables proper path completion (e.g., cd aaa/b<TAB> completes to aaa/bbb)
      Reline.completer_word_break_characters = " \t\n\"'><=;|&{("
      # Rebind Ctrl-W to backward_kill_word which stops at non-word characters like /
      # Default em_kill_region only stops at whitespace
      Reline.core.config.add_default_key_binding_by_keymap(:emacs, [23], :backward_kill_word)
      # Use autocompletion mode (fish-style inline suggestions)
      Reline.autocompletion = true

      # Set up key bindings for completion dialog navigation
      setup_completion_dialog_keybindings

      # Add abbreviated path expansion as a dialog proc
      # This expands l/r/re to lib/rubish/repl.rb inline when Tab is pressed
      setup_abbreviated_path_expansion
    end

    # Set terminal title to "rubish" (or custom title via RUBISH_TITLE env var)
    def setup_terminal_title
      return unless $stdout.tty?

      title = ENV['RUBISH_TITLE'] || 'rubish'
      # OSC 0 sets both window title and icon name
      # \e]0;title\a is the standard escape sequence
      print "\e]0;#{title}\a"
      $stdout.flush
    end

    # Check if a parse error indicates incomplete input (needs more lines)
    def incomplete_command_error?(message)
      # These patterns indicate the parser is waiting for a closing keyword/delimiter
      incomplete_patterns = [
        /Expected ['"]fi['"].*close if/,
        /Expected ['"]done['"].*close (while|until|for|select)/,
        /Expected ['"]esac['"].*close case/,
        /Expected ['"][}]['"].*close function/,
        /Expected ['"]end['"].*close (def|unless)/,
        /Expected ['"][)]?['"].*close (subshell|conditional)/,
        /Expected ['"]then['"]/,
        /Expected ['"]do['"]/,
        /Expected ['"]in['"]/,
        /Expected ['"]?\]\]?['"]?/,
      ]
      incomplete_patterns.any? { |pattern| message =~ pattern }
    end

    # Collect continuation lines for multi-line commands
    def collect_continuation_lines(accumulated_lines, initial_error)
      loop do
        begin
          cont_line = Reline.readline(continuation_prompt, false)
        rescue Interrupt
          puts
          return nil  # User cancelled
        end

        return nil unless cont_line  # EOF

        accumulated_lines << cont_line

        # Build full command (with newlines for lithist, semicolons otherwise)
        full_command = if Builtins.shopt_enabled?('lithist')
                         accumulated_lines.join("\n")
                       else
                         accumulated_lines.join('; ')
                       end

        # Try parsing again
        begin
          tokens = @lexer_class.new(full_command).tokenize
          ast = @parser_class.new(tokens).parse

          # Parsing succeeded - update history if cmdhist is enabled
          if Builtins.shopt_enabled?('cmdhist') && ast
            update_multiline_history(accumulated_lines)
          end

          return ast
        rescue => e
          if incomplete_command_error?(e.message)
            # Still incomplete, continue collecting
            next
          else
            # Real syntax error
            $stderr.puts "rubish: #{e.message}"
            return nil
          end
        end
      end
    end

    # Check for new mail based on MAIL/MAILPATH and MAILCHECK
    # MAIL: path to mail file to check
    # MAILPATH: colon-separated list of mail files, each optionally followed by ?message
    # MAILCHECK: interval in seconds between checks (default 60, 0 means check every prompt)
    def check_mail
      mailcheck = ENV['MAILCHECK']
      # If MAILCHECK is unset or empty, default to 60 seconds
      # If MAILCHECK is negative, disable checking
      check_interval = if mailcheck.nil? || mailcheck.empty?
                         60
                       else
                         mailcheck.to_i
                       end
      return if check_interval < 0

      # Check if enough time has passed since last check
      now = Time.now
      if check_interval > 0 && (now - @last_mail_check) < check_interval
        return
      end
      @last_mail_check = now

      # Get mail files to check
      mail_entries = parse_mail_paths

      mail_entries.each do |path, message|
        next unless File.exist?(path)
        next unless File.file?(path)
        next if File.size(path) == 0  # Empty mail file

        current_mtime = File.mtime(path)
        current_atime = File.atime(path)
        last_mtime = @mail_mtimes[path]
        last_atime = @mail_atimes[path]

        if last_mtime.nil?
          # First time seeing this file, just record times
          @mail_mtimes[path] = current_mtime
          @mail_atimes[path] = current_atime
        elsif current_mtime > last_mtime
          # File has been modified - new mail
          if message
            # Custom message from MAILPATH
            puts message
          else
            # Default message
            puts "You have new mail in #{path}"
          end
          @mail_mtimes[path] = current_mtime
          @mail_atimes[path] = current_atime
        elsif Builtins.shopt_enabled?('mailwarn')
          # mailwarn: check if mail has been read (atime > mtime and atime changed)
          if current_atime > current_mtime && (last_atime.nil? || current_atime > last_atime)
            puts "The mail in #{path} has been read"
            @mail_atimes[path] = current_atime
          end
        end
      end
    end

    # Parse MAILPATH or MAIL into list of [path, message] pairs
    def parse_mail_paths
      mailpath = ENV['MAILPATH']

      if mailpath && !mailpath.empty?
        # MAILPATH format: /path/to/mail?message:/another/path?another message
        mailpath.split(':').map do |entry|
          if entry.include?('?')
            path, message = entry.split('?', 2)
            [path, message]
          else
            [entry, nil]
          end
        end
      elsif ENV['MAIL'] && !ENV['MAIL'].empty?
        # Fall back to MAIL (single file, no custom message)
        [[ENV['MAIL'], nil]]
      else
        []
      end
    end

    def process_line
      # Check for completed background jobs
      JobManager.instance.check_background_jobs

      # Check for new mail (before prompt)
      check_mail

      # Execute any commands that were typed during startup (before prompt appeared)
      if @pending_commands && !@pending_commands.empty?
        line = @pending_commands.shift
        # Show the command as if it was typed (with prompt)
        puts "#{prompt}#{line}"
        # Execute it
        execute(line)
        return
      end

      # Execute PROMPT_COMMAND before displaying prompt
      run_prompt_command

      # Get the left prompt
      left_prompt = prompt

      # Set Reline's rprompt for right-side prompt
      setup_rprompt

      # Don't auto-add to history; we'll do it ourselves after checking HISTCONTROL/HISTIGNORE
      line = Reline.readline(left_prompt, false)
      unless line
        # EOF received (Ctrl+D)
        # Check IGNOREEOF variable first, then fall back to set -o ignoreeof
        ignoreeof_value = ENV['IGNOREEOF']
        if ignoreeof_value || Builtins.set_option?('ignoreeof')
          # Parse IGNOREEOF value: if set but empty or non-numeric, default to 10
          max_eof = if ignoreeof_value
                      val = ignoreeof_value.to_i
                      (ignoreeof_value.empty? || val < 0) ? 10 : val
                    else
                      10  # Default for set -o ignoreeof
                    end
          @eof_count += 1
          if @eof_count > max_eof
            puts 'exit'
            return throw(:exit, 0)
          else
            remaining = max_eof - @eof_count + 1
            puts "\nUse \"exit\" to leave the shell, or press Ctrl+D #{remaining} more time#{'s' if remaining != 1}."
            return
          end
        else
          puts 'exit'
          return throw(:exit, 0)
        end
      end

      line = line.strip
      return if line.empty?

      # Reset EOF counter when user types a command
      @eof_count = 0

      # Expand history BEFORE adding to history (so !! doesn't expand to itself)
      expanded_line, was_expanded, failed = expand_history(line)
      return if failed
      return unless expanded_line

      # histverify: if history expansion occurred, let user verify before executing
      if was_expanded && Builtins.shopt_enabled?('histverify')
        # Pre-fill the expanded command for user to verify/edit
        Reline.pre_input_hook = -> {
          Reline.insert_text(expanded_line)
          Reline.pre_input_hook = nil  # Clear after use
        }
        return  # Don't execute, let user verify on next prompt
      end

      # Print expanded command if history expansion occurred
      puts expanded_line if was_expanded

      # Add the EXPANDED command to history (like bash does)
      add_to_history(expanded_line)

      # Print PS0 before executing command (bash 4.4+ feature)
      print_ps0

      @last_line = expanded_line
      execute(expanded_line, skip_history_expansion: true)

      # checkwinsize: update LINES and COLUMNS after each command
      check_window_size if Builtins.shopt_enabled?('checkwinsize')

      # onecmd: exit after reading and executing one command
      throw(:exit, @last_status || 0) if Builtins.set_option?('t')
    rescue Interrupt
      puts
    rescue Errno::EIO
      # Ignore I/O errors from terminal control issues during job control
    rescue => e
      puts "rubish: #{e.message}"
    end

    # Execute a shell command from bind -x key binding
    # This is called from within Reline's key handling, so we need to be careful
    # about terminal state and output
    def execute_bind_x_command(command)
      begin
        # Execute the command using the same mechanism as regular commands
        # but skip history expansion and recording
        line = Builtins.expand_alias(command)
        line = expand_tilde(line)

        # Strip comments if enabled
        if Builtins.shopt_enabled?('interactive_comments')
          line = strip_comment(line)
          return if line.empty?
        end

        tokens = Lexer.new(line).tokenize
        return if tokens.empty?

        ast = Parser.new(tokens).parse
        return unless ast

        # Check for user-defined functions (like normal execute does)
        if ast.is_a?(AST::Command) && @functions.key?(ast.name)
          expanded_args = expand_args_for_builtin(ast.args)
          call_function(ast.name, expanded_args)
          return
        end

        # Generate and execute code using eval_in_context which handles
        # running Command objects and function calls with redirects
        code = Codegen.new.generate(ast)
        eval_in_context(code)
      rescue Interrupt
        # User interrupted the command
        puts
      rescue => e
        $stderr.puts "bind -x: #{e.message}" if ENV['RUBISH_DEBUG']
      end

      # Redraw the prompt - Reline will handle this when we return
    end

    def execute(line, skip_history_expansion: false)
      # verbose: print input lines as read (before any processing)
      $stderr.puts line if Builtins.set_option?('v')

      unless skip_history_expansion
        original_line = line
        line, expanded, failed = expand_history(line)

        # histreedit: if history expansion failed, reload line for editing
        if failed && Builtins.shopt_enabled?('histreedit')
          Reline.pre_input_hook = -> {
            Reline.insert_text(original_line)
            Reline.pre_input_hook = nil  # Clear after use
          }
          return
        end

        return unless line

        # Print expanded command if history expansion occurred
        puts line if expanded
      end

      line = Builtins.expand_alias(line)
      line = expand_tilde(line)

      # interactive_comments: strip comments (text after unquoted #)
      if Builtins.shopt_enabled?('interactive_comments')
        line = strip_comment(line)
        return if line.empty?
      end

      # Set RUBISH_COMMAND before execution (contains command being executed)
      @rubish_command = line

      # xtrace: print commands before execution (after expansion)
      xtrace(line) if Builtins.set_option?('x')

      # Check if input looks like a Ruby expression (starts with capital letter)
      # UNIX commands rarely start with capitals, but Ruby constants/classes do
      # Exclude shell variable assignments (VAR=value, VAR+=value, VAR[n]=value)
      if line =~ /\A[A-Z]/ && line !~ /\A[A-Z_][A-Z0-9_]*(\[[^\]]*\])?\+?=/
        begin
          result = @context.instance_eval(line)
          p result unless result.nil?
        rescue SyntaxError, StandardError => e
          $stderr.puts "rubish: #{e.message}"
          @last_status = 1
          return
        end
        @last_status = 0
        @context.clear_exit_blocked
        return
      end

      # Check if input is a Ruby lambda literal (-> { ... } or ->(args) { ... })
      if line =~ /\A->/
        begin
          result = @context.instance_eval(line)
          # Auto-call lambdas with no required arguments
          result = result.call if result.is_a?(Proc) && result.arity <= 0
          p result unless result.nil?
        rescue SyntaxError, StandardError => e
          $stderr.puts "rubish: #{e.message}"
          @last_status = 1
          return
        end
        @last_status = 0
        @context.clear_exit_blocked
        return
      end

      # Check for array assignment before tokenizing (arr=(a b c) pattern)
      if (array_assignments = extract_array_assignments(line))
        handle_bare_assignments(array_assignments)
        @last_status = 0
        Builtins.clear_exit_blocked  # checkjobs: non-exit command resets flag
        return
      end

      # Variable expansion now happens at runtime in generated Ruby code
      # Handle multi-line commands (cmdhist): collect continuation lines if parse fails
      accumulated_lines = [line]
      tokens = @lexer_class.new(line).tokenize
      begin
        ast = @parser_class.new(tokens).parse
      rescue => e
        # Check if this is an incomplete command that needs more input
        if incomplete_command_error?(e.message)
          # Prompt for continuation lines until parsing succeeds
          ast = collect_continuation_lines(accumulated_lines, e)
          return unless ast  # User cancelled (Ctrl+C) or error
        else
          raise  # Re-raise actual syntax errors
        end
      end
      return unless ast

      # noexec: parse but don't execute (except 'set' to allow disabling noexec)
      if Builtins.set_option?('n')
        # Allow 'set' command through so we can turn noexec off
        unless ast.is_a?(AST::Command) && ast.name == 'set'
          @last_status = 0
          return
        end
      end

      # Check for heredocs and collect content if needed
      # Skip if content was already set (e.g., by source command)
      if (heredoc = find_heredoc(ast)) && @heredoc_content.nil?
        @heredoc_content = collect_heredoc_content(heredoc.delimiter, heredoc.strip_tabs)
        # Update history with full heredoc command if cmdhist is enabled
        update_history_with_heredoc(line, heredoc.delimiter, @heredoc_content)
      end

      # Check for bare variable assignment (VAR=value or VAR=value VAR2=value2 ...)
      if ast.is_a?(AST::Command) && bare_assignment?(ast.name) && ast.args.all? { |a| bare_assignment?(a) }
        handle_bare_assignments([ast.name] + ast.args)
        @last_status = 0
        @pipestatus = [0]
        @command_number += 1
        # Note: bare assignments don't increment LINENO (bash behavior)
        Builtins.clear_exit_blocked  # checkjobs: non-exit command resets flag
        return
      end

      # Check for builtins (simple command only)
      if ast.is_a?(AST::Command) && Builtins.builtin?(ast.name)
        builtin_name = ast.name
        begin
          # Run DEBUG trap before command
          Builtins.debug_trap

          # Expand variables in args for builtins
          expanded_args = expand_args_for_builtin(ast.args)
          result = Builtins.run(builtin_name, expanded_args)
          @last_status = result ? 0 : 1
          @pipestatus = [@last_status]
          run_err_trap_if_failed
          check_errexit
        rescue NounsetError
          @last_status = 1
          @pipestatus = [@last_status]
          throw(:exit, 1) if Builtins.set_option?('u')
        rescue FailglobError
          @last_status = 1
          @pipestatus = [@last_status]
        ensure
          @command_number += 1
          @lineno += 1
          # checkjobs: non-exit/logout commands reset the flag
          Builtins.clear_exit_blocked unless %w[exit logout].include?(builtin_name)
        end
        return
      end

      # Check for autoloaded functions that need to be loaded
      if ast.is_a?(AST::Command) && Builtins.autoload_pending?(ast.name)
        Builtins.load_autoload_function(ast.name)
      end

      # Check for user-defined functions (simple command only)
      if ast.is_a?(AST::Command) && @functions.key?(ast.name)
        begin
          # Run DEBUG trap before function call
          Builtins.debug_trap

          expanded_args = expand_args_for_builtin(ast.args)
          result = call_function(ast.name, expanded_args)
          @last_status = result ? 0 : 1
          @pipestatus = [@last_status]
          # Don't run ERR trap here - it was already handled inside the function if errtrace is on
          check_errexit
        rescue NounsetError
          @last_status = 1
          @pipestatus = [@last_status]
          throw(:exit, 1) if Builtins.set_option?('u')
        rescue FailglobError
          @last_status = 1
          @pipestatus = [@last_status]
        ensure
          @command_number += 1
          @lineno += 1
          Builtins.clear_exit_blocked  # checkjobs: non-exit command resets flag
        end
        return
      end

      # autocd: if command is a directory and autocd is enabled, cd to it
      if ast.is_a?(AST::Command) && ast.args.empty? && Builtins.shopt_enabled?('autocd')
        dir = expand_single_arg(ast.name)
        if File.directory?(dir)
          result = Builtins.run('cd', [dir])
          @last_status = result ? 0 : 1
          @pipestatus = [@last_status]
          @command_number += 1
          @lineno += 1
          Builtins.clear_exit_blocked  # checkjobs: non-exit command resets flag
          return
        end
      end

      code = @codegen.generate(ast)
      result = eval_in_context(code)

      # Special handling for exec with redirections
      if result.is_a?(Command) && result.name == 'exec'
        handle_exec_command(result)
      else
        @last_status = extract_exit_status(result)
      end
      @command_number += 1
      @lineno += 1
      Builtins.clear_exit_blocked  # checkjobs: non-exit command resets flag
      check_errexit
    rescue NounsetError
      # Unbound variable error when set -u is enabled
      @last_status = 1
      throw(:exit, 1) if Builtins.set_option?('u')
    rescue FailglobError
      # Glob pattern matched nothing with failglob enabled
      @last_status = 1
    ensure
      @heredoc_content = nil
    end

    def xtrace(line)
      # Print trace with PS4 prefix (default: '+ ')
      # PS4 supports the same escape sequences as PS1
      ps4 = ENV['PS4'] || '+ '
      expanded_ps4 = expand_prompt(ps4)
      output = "#{expanded_ps4}#{line}"

      # Check RUBISH_XTRACEFD (or BASH_XTRACEFD for compatibility)
      xtracefd = ENV['RUBISH_XTRACEFD'] || ENV['BASH_XTRACEFD']
      if xtracefd && !xtracefd.empty?
        fd_num = xtracefd.to_i
        if fd_num >= 0 && xtracefd =~ /\A\d+\z/
          begin
            # Use IO.for_fd with autoclose: false to avoid closing the fd when done
            io = IO.for_fd(fd_num, 'w', autoclose: false)
            io.puts output
            io.flush
          rescue Errno::EBADF
            # Invalid file descriptor, fall back to stderr
            $stderr.puts "rubish: #{fd_num}: Bad file descriptor"
            $stderr.puts output
          rescue => e
            $stderr.puts output
          end
        else
          # Not a valid number, use stderr
          $stderr.puts output
        end
      else
        $stderr.puts output
      end
    end

    def check_errexit
      return if @last_status == 0

      # Exit if errexit is set and last command failed
      # Note: ERR trap is run in __run_cmd at command execution time
      if Builtins.set_option?('e')
        throw(:exit, @last_status)
      end
    end

    def execute_command_directly(args)
      # Execute a command directly without checking functions or aliases
      # This is used by the 'command' builtin to bypass functions
      return true if args.empty?

      name = args.first
      cmd_args = args[1..] || []

      # Check if it's a builtin first
      if Builtins.builtin?(name)
        Builtins.run(name, cmd_args)
      else
        # Run as external command, skipping function lookup
        cmd = Command.new(name, *cmd_args, skip_functions: true)
        cmd.run
        @last_status = cmd.success? ? 0 : 1
        cmd.success?
      end
    end

    def call_function(name, args)
      func_info = @functions[name]
      return false unless func_info

      # Check FUNCNEST limit
      funcnest = ENV['FUNCNEST']
      if funcnest && !funcnest.empty?
        max_depth = funcnest.to_i
        if max_depth > 0 && @funcname_stack.length >= max_depth
          $stderr.puts Builtins.format_error("maximum function nesting level exceeded (#{max_depth})", command: name)
          @last_status = 1
          return false
        end
      end

      # Extract block and source from function info
      func_block = func_info[:block]
      func_source = func_info[:source]

      # Push function name onto FUNCNAME stack, line number onto RUBISH_LINENO stack, source onto RUBISH_SOURCE stack
      @funcname_stack.unshift(name)
      @rubish_lineno_stack.unshift(@lineno)
      @rubish_source_stack.unshift(func_source)
      # Push argument count onto RUBISH_ARGC stack, and args onto RUBISH_ARGV stack
      @rubish_argc_stack.unshift(args.length)
      # BASH_ARGV stores args with last arg at top of stack (index 0)
      # Iterating forward and unshifting gives us: args[0], args[1], args[2] -> [args[2], args[1], args[0]]
      args.each { |arg| @rubish_argv_stack.unshift(arg) }

      # Save current positional params and set new ones
      saved_params = @positional_params
      @positional_params = args
      # Sync positional params to context so function body can access them
      @context.instance_variable_set(:@positional_params, @positional_params)

      # Push a new local scope for this function
      Builtins.push_local_scope

      # Set local variables from named parameters (Ruby-style def)
      if func_info[:params]
        func_info[:params].each_with_index do |param_name, i|
          if param_name.start_with?('*')
            # Splat param: capture all remaining args as array
            splat_name = param_name[1..]
            Builtins.set_array(splat_name, args[i..] || [])
          else
            Builtins.set_local_from_param(param_name, args[i] || '')
          end
        end
      end

      # If errtrace is not set, ERR trap is not inherited by functions
      saved_err_trap = nil
      unless Builtins.set_option?('E')
        saved_err_trap = Builtins.save_and_clear_err_trap
      end

      # If functrace is not set, DEBUG/RETURN traps are not inherited by functions
      saved_functrace_traps = nil
      unless Builtins.set_option?('T')
        saved_functrace_traps = Builtins.save_and_clear_functrace_traps
      end

      begin
        result = func_block.call
        # Handle return value
        if result.is_a?(Command) || result.is_a?(Pipeline)
          result.success?
        else
          true
        end
      rescue LocalJumpError
        # return was called in function
        true
      ensure
        # Run RETURN trap before leaving function (if functrace is on, trap exists)
        Builtins.return_trap

        # Restore ERR trap if we cleared it
        Builtins.restore_err_trap(saved_err_trap) if saved_err_trap

        # Restore DEBUG/RETURN traps if we cleared them
        Builtins.restore_functrace_traps(saved_functrace_traps) if saved_functrace_traps

        # Pop local scope and restore variables
        Builtins.pop_local_scope
        @positional_params = saved_params
        # Sync restored params back to context
        @context.instance_variable_set(:@positional_params, @positional_params)

        # Pop function name from FUNCNAME stack, line number from RUBISH_LINENO stack, source from RUBISH_SOURCE stack
        @funcname_stack.shift
        @rubish_lineno_stack.shift
        @rubish_source_stack.shift
        # Pop argument count from RUBISH_ARGC stack, and corresponding args from RUBISH_ARGV stack
        argc = @rubish_argc_stack.shift || 0
        argc.times { @rubish_argv_stack.shift }
      end
    end


    def eval_in_context(code)
      # Sync REPL state to context before eval
      @context.last_status = @last_status
      @context.last_bg_pid = @last_bg_pid
      @context.lineno = @lineno
      @context.pipestatus = @pipestatus
      @context.functions = @functions
      @context.heredoc_content = @heredoc_content
      @context.instance_variable_set(:@positional_params, @positional_params)
      @context.instance_variable_set(:@argv0, @script_name)
      @context.instance_variable_set(:@script_name, @script_name)
      @context.instance_variable_set(:@funcname_stack, @funcname_stack)
      @context.instance_variable_set(:@rubish_lineno_stack, @rubish_lineno_stack)
      @context.instance_variable_set(:@rubish_source_stack, @rubish_source_stack)
      @context.instance_variable_set(:@rubish_argc_stack, @rubish_argc_stack)
      @context.instance_variable_set(:@rubish_argv_stack, @rubish_argv_stack)
      @context.instance_variable_set(:@rubish_command, @rubish_command)
      @context.instance_variable_set(:@current_source_file, @current_source_file)
      @context.instance_variable_set(:@command_number, @command_number)
      @context.instance_variable_set(:@seconds_base, @seconds_base)
      @context.instance_variable_set(:@random_generator, @random_generator)
      @context.instance_variable_set(:@bash_argv0_unset, @bash_argv0_unset)
      @context.subshell_level = @subshell_level

      result = @context.instance_eval(code)
      if result.is_a?(Command) && result.name == 'exec'
        # Don't auto-run exec - it's handled specially in execute method
        # to support redirections without command replacement
        result
      elsif result.is_a?(Command) && @functions.key?(result.name)
        # Call user-defined function, handling redirects
        call_function_with_redirects(result)
        @pipestatus = [@last_status]
      elsif result.is_a?(Command) && bare_assignment?(result.name) && result.args.all? { |a| bare_assignment?(a) }
        # Handle bare variable assignments (e.g., x=$(echo hello) after expansion)
        handle_bare_assignments([result.name] + result.args)
        @last_status = 0
        @pipestatus = [0]
      elsif result.is_a?(Command) || result.is_a?(Pipeline) || result.is_a?(Subshell) || result.is_a?(HeredocCommand)
        result.run
        # Update PIPESTATUS array
        if result.respond_to?(:status)
          @last_status = result.status&.exitstatus || 0
          if result.is_a?(Pipeline) && result.statuses
            @pipestatus = result.statuses.map { |s| s.exitstatus || 0 }
          else
            @pipestatus = [@last_status]
          end
        end
      end

      # Sync context state back to REPL
      @seconds_base = @context.instance_variable_get(:@seconds_base)
      @random_generator = @context.instance_variable_get(:@random_generator)
      @last_bg_pid = @context.last_bg_pid

      result
    end

    def call_function_with_redirects(cmd)
      # Set up redirects if present
      saved_stdout = nil
      saved_stdin = nil

      begin
        if cmd.stdout
          saved_stdout = $stdout.dup
          $stdout.reopen(cmd.stdout)
        end
        if cmd.stdin
          saved_stdin = $stdin.dup
          $stdin.reopen(cmd.stdin)
        end

        success = call_function(cmd.name, cmd.args)
        @last_status = success ? 0 : 1
      ensure
        if saved_stdout
          $stdout.reopen(saved_stdout)
          saved_stdout.close
          cmd.stdout.close unless cmd.stdout.closed?
        end
        if saved_stdin
          $stdin.reopen(saved_stdin)
          saved_stdin.close
          cmd.stdin.close unless cmd.stdin.closed?
        end
      end
    end

    # Ruby methods for builtins - usable in blocks
    def echo(*args)
      Builtins.echo(args.map(&:to_s))
    end

    def printf(*args)
      Builtins.printf(args.map(&:to_s))
    end

    # Allocate a new FD number for {varname} redirection
    def allocate_varname_fd
      fd = @next_varname_fd
      @next_varname_fd += 1
      # Skip over any FDs that are already in use
      while @varname_fds.values.any? { |info| info[:fd] == @next_varname_fd }
        @next_varname_fd += 1
      end
      fd
    end

    # Perform redirection with allocated FD
    def perform_varname_redirect(fd_num, io, &block)
      result = block.call
      # Store the IO object for later use
      @varname_fds.each do |name, info|
        if info[:fd] == fd_num
          info[:io] = io
          break
        end
      end
      result
    ensure
      # Don't close here - the FD should remain open for use
      # It will be closed by varredir_close or explicit close
    end

    # Perform FD duplication
    def perform_fd_dup(fd_num, src_fd, &block)
      block.call
    end

    # Close a varname-allocated FD
    def close_varname_fd(varname)
      info = @varname_fds.delete(varname)
      return unless info

      if info[:io] && !info[:io].closed?
        info[:io].close
      end
      ENV.delete(varname)
    end

    # Close a specific FD by number (for explicit close like exec {fd}>&-)
    def close_fd_by_number(fd_num)
      @varname_fds.each do |name, info|
        if info[:fd] == fd_num
          close_varname_fd(name)
          break
        end
      end
    end

    def display_select_menu(items)
      # Calculate column width for nice formatting
      max_len = items.map(&:length).max || 0
      num_width = items.length.to_s.length

      items.each_with_index do |item, i|
        puts "#{(i + 1).to_s.rjust(num_width)}) #{item}"
      end
    end

    # Expand abbreviated path: l/r/repl.rb -> lib/rubish/repl.rb
    def expand_abbreviated_path(path)
      Builtins.expand_abbreviated_path(path)
    end

    # Apply GLOBIGNORE filtering to glob results
    # GLOBIGNORE is a colon-separated list of patterns to exclude
    def apply_globignore(matches)
      globignore = ENV['GLOBIGNORE']
      return matches if globignore.nil? || globignore.empty?

      patterns = globignore.split(':').reject(&:empty?)
      return matches if patterns.empty?

      # Always filter out . and .. when GLOBIGNORE is set
      matches = matches.reject { |m| m == '.' || m == '..' || m.end_with?('/.') || m.end_with?('/..') }

      # Filter matches against GLOBIGNORE patterns
      matches.reject do |match|
        basename = File.basename(match)
        patterns.any? do |pattern|
          File.fnmatch?(pattern, basename, File::FNM_DOTMATCH) ||
            File.fnmatch?(pattern, match, File::FNM_DOTMATCH)
        end
      end
    end

    # Apply GLOBSORT sorting to glob results
    # GLOBSORT controls the sort order of glob expansion results
    # Values: name (default), size, mtime, atime, ctime, blocks, extension, nosort
    # Prefix with - for reverse order (e.g., -size for largest first)
    def apply_globsort(matches)
      return matches if matches.empty?

      globsort = ENV['GLOBSORT']
      # Default is alphabetical sort by name
      return matches.sort if globsort.nil? || globsort.empty? || globsort == 'name'

      # Check for reverse flag
      reverse = globsort.start_with?('-')
      sort_type = reverse ? globsort[1..] : globsort

      sorted = case sort_type
               when 'name'
                 matches.sort
               when 'nosort', 'none'
                 matches  # No sorting, return as-is from readdir
               when 'size'
                 matches.sort_by { |f| File.exist?(f) ? File.size(f) : 0 }
               when 'mtime'
                 matches.sort_by { |f| File.exist?(f) ? File.mtime(f) : Time.at(0) }
               when 'atime'
                 matches.sort_by { |f| File.exist?(f) ? File.atime(f) : Time.at(0) }
               when 'ctime'
                 matches.sort_by { |f| File.exist?(f) ? File.ctime(f) : Time.at(0) }
               when 'blocks'
                 matches.sort_by { |f| File.exist?(f) ? (File.stat(f).blocks rescue 0) : 0 }
               when 'extension'
                 matches.sort_by { |f| [File.extname(f).downcase, f.downcase] }
               when 'numeric'
                 # Numeric sort: extract numbers from filenames and sort numerically
                 # file1.txt < file2.txt < file10.txt (not file1 < file10 < file2)
                 matches.sort_by { |f| numeric_sort_key(f) }
               else
                 # Unknown sort type, fall back to name sort
                 matches.sort
               end

      reverse ? sorted.reverse : sorted
    end

    # Generate a sort key for numeric sorting
    # Splits filename into alternating text/number parts for natural sorting
    # "file10.txt" -> ["file", 10, ".txt"] so file2 < file10
    def numeric_sort_key(filename)
      # Split into alternating non-digit and digit parts
      parts = filename.scan(/\D+|\d+/)
      parts.map do |part|
        if part =~ /^\d+$/
          # Pad numbers to ensure proper numeric comparison
          part.to_i
        else
          part.downcase
        end
      end
    end

    # POSIX character class mappings for glob patterns
    # These map [:classname:] to equivalent character sets
    POSIX_CHAR_CLASSES = {
      'alnum' => 'a-zA-Z0-9',
      'alpha' => 'a-zA-Z',
      'ascii' => '\x00-\x7F',
      'blank' => ' \t',
      'cntrl' => '\x00-\x1F\x7F',
      'digit' => '0-9',
      'graph' => '!-~',           # printable chars except space (ASCII 33-126)
      'lower' => 'a-z',
      'print' => ' -~',           # printable chars including space (ASCII 32-126)
      'punct' => '!-/:-@\\[-`{-~', # punctuation characters
      'space' => ' \t\n\r\f\v',
      'upper' => 'A-Z',
      'word' => 'a-zA-Z0-9_',
      'xdigit' => '0-9A-Fa-f'
    }.freeze

    def expand_posix_classes(pattern)
      # Expand POSIX character classes in bracket expressions
      # e.g., [[:digit:]] -> [0-9], [[:alpha:][:digit:]] -> [a-zA-Z0-9]
      return pattern unless pattern.include?('[:')

      result = +''
      i = 0
      while i < pattern.length
        if pattern[i] == '['
          # Find the end of this bracket expression
          bracket_start = i
          j = i + 1

          # Handle negation
          j += 1 if j < pattern.length && (pattern[j] == '!' || pattern[j] == '^')
          # Handle literal ] at start
          j += 1 if j < pattern.length && pattern[j] == ']'

          # Find the closing ] while skipping POSIX class brackets
          while j < pattern.length
            if pattern[j] == '[' && j + 1 < pattern.length && pattern[j + 1] == ':'
              # This is a POSIX class [:...:] - find its end
              end_pos = pattern.index(':]', j + 2)
              if end_pos
                j = end_pos + 2
              else
                j += 1
              end
            elsif pattern[j] == ']'
              # Found the closing bracket
              break
            else
              j += 1
            end
          end

          if j < pattern.length && pattern[j] == ']'
            # Extract bracket expression and expand POSIX classes
            bracket_expr = pattern[bracket_start..j]
            expanded = expand_posix_in_bracket(bracket_expr)
            result << expanded
            i = j + 1
          else
            result << pattern[i]
            i += 1
          end
        else
          result << pattern[i]
          i += 1
        end
      end
      result
    end

    def expand_posix_in_bracket(bracket_expr)
      # Expand POSIX classes within a bracket expression
      # [[:digit:]] -> [0-9]
      # [[:alpha:][:digit:]] -> [a-zA-Z0-9]
      # [^[:digit:]] -> [^0-9]
      # [a[:digit:]] -> [a0-9]

      return bracket_expr unless bracket_expr.include?('[:')

      # Extract content between [ and ]
      content = bracket_expr[1...-1]

      # Check for negation
      negation = ''
      if content.start_with?('!') || content.start_with?('^')
        negation = content[0]
        content = content[1..]
      end

      # Expand all POSIX classes
      expanded_content = content.gsub(/\[:([a-z]+):\]/) do |match|
        class_name = $1
        if POSIX_CHAR_CLASSES.key?(class_name)
          POSIX_CHAR_CLASSES[class_name]
        else
          # Unknown class, keep as-is (will likely fail to match)
          match
        end
      end

      "[#{negation}#{expanded_content}]"
    end

    def expand_locale_ranges(pattern)
      # When globasciiranges is disabled, expand letter ranges to include both cases
      # This approximates locale-aware collation where [a-z] might match A-Z too
      # Transform [a-z] to [a-zA-Z], [A-Z] to [A-Za-z], etc.
      result = +''
      i = 0
      while i < pattern.length
        if pattern[i] == '['
          # Find the end of the bracket expression
          j = i + 1
          j += 1 if j < pattern.length && (pattern[j] == '!' || pattern[j] == '^')  # negation
          j += 1 if j < pattern.length && pattern[j] == ']'  # literal ] at start
          while j < pattern.length && pattern[j] != ']'
            j += 1
          end
          if j < pattern.length
            # Extract bracket contents and expand ranges
            bracket_content = pattern[i + 1...j]
            expanded = expand_bracket_ranges(bracket_content)
            result << '[' << expanded << ']'
            i = j + 1
          else
            result << pattern[i]
            i += 1
          end
        else
          result << pattern[i]
          i += 1
        end
      end
      result
    end

    def expand_bracket_ranges(content)
      # Expand letter ranges in bracket expression to include both cases
      # e.g., "a-z" becomes "a-zA-Z", "A-M" becomes "A-Ma-m"
      result = +''
      i = 0

      # Handle negation prefix
      if i < content.length && (content[i] == '!' || content[i] == '^')
        result << content[i]
        i += 1
      end

      while i < content.length
        # Check for a range pattern: char-char
        if i + 2 < content.length && content[i + 1] == '-' && content[i + 2] != ']'
          start_char = content[i]
          end_char = content[i + 2]

          # Check if this is a letter range
          if start_char =~ /[a-zA-Z]/ && end_char =~ /[a-zA-Z]/
            # Add the original range
            result << start_char << '-' << end_char
            # Add the opposite case range if it's a single-case range
            if start_char =~ /[a-z]/ && end_char =~ /[a-z]/
              # Lowercase range - add uppercase equivalent
              result << start_char.upcase << '-' << end_char.upcase
            elsif start_char =~ /[A-Z]/ && end_char =~ /[A-Z]/
              # Uppercase range - add lowercase equivalent
              result << start_char.downcase << '-' << end_char.downcase
            end
            i += 3
          else
            # Not a letter range, keep as-is
            result << content[i]
            i += 1
          end
        else
          result << content[i]
          i += 1
        end
      end

      result
    end

    def has_extglob?(pattern)
      # Check if pattern contains extended glob operators: ?() *() +() @() !()
      pattern.match?(/[?*+@!]\([^)]*\)/)
    end

    def expand_extglob(pattern)
      # Convert extended glob pattern to regex and match files
      # First, get the directory to search in
      dir = File.dirname(pattern)
      dir = '.' if dir == pattern || dir.empty?

      # Build regex from the pattern
      regex = extglob_to_regex(File.basename(pattern))

      # Get all files in directory and filter by regex
      begin
        entries = if pattern.include?('/')
                    # For paths with directories, we need to handle differently
                    base_glob = pattern.gsub(/[?*+@!]\([^)]*\)/, '*')
                    Dir.glob(base_glob)
                  else
                    Dir.entries(dir).reject { |e| e.start_with?('.') }
                  end

        if pattern.include?('/')
          # Filter full paths
          full_regex = extglob_to_regex(pattern)
          entries.select { |f| f.match?(full_regex) }.sort
        else
          entries.select { |f| f.match?(regex) }.map { |f| dir == '.' ? f : File.join(dir, f) }.sort
        end
      rescue Errno::ENOENT
        []
      end
    end

    def extglob_to_regex(pattern)
      # Convert extended glob pattern to Ruby regex
      result = +''
      i = 0

      while i < pattern.length
        char = pattern[i]

        case char
        when '\\'
          # Escape next character
          result << Regexp.escape(pattern[i + 1] || '')
          i += 2
        when '?'
          if pattern[i + 1] == '('
            # ?(pattern) - zero or one
            end_idx = find_matching_paren(pattern, i + 1)
            inner = pattern[i + 2...end_idx]
            result << "(?:#{extglob_alternatives_to_regex(inner)})?"
            i = end_idx + 1
          else
            # Regular ? glob - match any single character
            result << '.'
            i += 1
          end
        when '*'
          if pattern[i + 1] == '('
            # *(pattern) - zero or more
            end_idx = find_matching_paren(pattern, i + 1)
            inner = pattern[i + 2...end_idx]
            result << "(?:#{extglob_alternatives_to_regex(inner)})*"
            i = end_idx + 1
          else
            # Regular * glob - match any characters
            result << '.*'
            i += 1
          end
        when '+'
          if pattern[i + 1] == '('
            # +(pattern) - one or more
            end_idx = find_matching_paren(pattern, i + 1)
            inner = pattern[i + 2...end_idx]
            result << "(?:#{extglob_alternatives_to_regex(inner)})+"
            i = end_idx + 1
          else
            result << Regexp.escape(char)
            i += 1
          end
        when '@'
          if pattern[i + 1] == '('
            # @(pattern) - exactly one
            end_idx = find_matching_paren(pattern, i + 1)
            inner = pattern[i + 2...end_idx]
            result << "(?:#{extglob_alternatives_to_regex(inner)})"
            i = end_idx + 1
          else
            result << Regexp.escape(char)
            i += 1
          end
        when '!'
          if pattern[i + 1] == '('
            # !(pattern) - anything except
            end_idx = find_matching_paren(pattern, i + 1)
            inner = pattern[i + 2...end_idx]
            result << "(?!#{extglob_alternatives_to_regex(inner)}).*"
            i = end_idx + 1
          else
            result << Regexp.escape(char)
            i += 1
          end
        when '['
          # Character class - find the closing ]
          end_idx = pattern.index(']', i + 1)
          if end_idx
            result << pattern[i..end_idx]
            i = end_idx + 1
          else
            result << Regexp.escape(char)
            i += 1
          end
        when '.'
          result << '\\.'
          i += 1
        else
          result << Regexp.escape(char)
          i += 1
        end
      end

      Regexp.new("\\A#{result}\\z")
    end

    def extglob_alternatives_to_regex(inner)
      # Convert pipe-separated alternatives to regex alternatives
      # Handle nested patterns
      alternatives = split_extglob_alternatives(inner)
      alternatives.map { |alt| extglob_simple_to_regex(alt) }.join('|')
    end

    def split_extglob_alternatives(inner)
      # Split on | but respect nested parentheses
      result = []
      current = +''
      depth = 0

      inner.each_char do |char|
        case char
        when '('
          depth += 1
          current << char
        when ')'
          depth -= 1
          current << char
        when '|'
          if depth == 0
            result << current
            current = +''
          else
            current << char
          end
        else
          current << char
        end
      end
      result << current unless current.empty?
      result
    end

    def extglob_simple_to_regex(pattern)
      # Convert simple glob pattern (inside extglob parens) to regex
      result = +''
      i = 0

      while i < pattern.length
        char = pattern[i]
        case char
        when '*'
          result << '.*'
        when '?'
          result << '.'
        when '['
          end_idx = pattern.index(']', i + 1)
          if end_idx
            result << pattern[i..end_idx]
            i = end_idx
          else
            result << Regexp.escape(char)
          end
        when '.'
          result << '\\.'
        else
          result << Regexp.escape(char)
        end
        i += 1
      end
      result
    end

    def find_matching_paren(str, start_idx)
      depth = 0
      i = start_idx
      while i < str.length
        case str[i]
        when '('
          depth += 1
        when ')'
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end
      str.length
    end

    def cleanup_proc_sub_fifos
      return unless @proc_sub_fifos

      @proc_sub_fifos.each do |fifo|
        File.unlink(fifo) if File.exist?(fifo)
      rescue Errno::ENOENT
        # Already deleted
      end
      @proc_sub_fifos.clear
    end

    def expand_braces(str)
      # Find the first brace group to expand
      # Return array of expanded strings
      return [str] unless str.include?('{')

      # Find matching braces, handling nesting
      start_idx = nil
      depth = 0
      i = 0

      while i < str.length
        case str[i]
        when '\\'
          i += 2  # Skip escaped character
          next
        when '{'
          start_idx = i if depth == 0
          depth += 1
        when '}'
          depth -= 1
          if depth == 0 && start_idx
            # Found a complete brace group
            prefix = str[0...start_idx]
            suffix = str[i + 1..]
            content = str[start_idx + 1...i]

            # Check if it's a sequence {a..b}, {a..b..step} or a list {a,b,c}
            expansions = if content =~ /\A(-?\d+)\.\.(-?\d+)\.\.(-?\d+)\z/
                           expand_numeric_sequence($1, $2, $3.to_i)
                         elsif content =~ /\A(-?\d+)\.\.(-?\d+)\z/
                           expand_numeric_sequence($1, $2)
                         elsif content =~ /\A([a-zA-Z])\.\.([a-zA-Z])\.\.(-?\d+)\z/
                           expand_letter_sequence($1, $2, $3.to_i)
                         elsif content =~ /\A([a-zA-Z])\.\.([a-zA-Z])\z/
                           expand_letter_sequence($1, $2)
                         elsif content.include?(',')
                           expand_brace_list(content)
                         else
                           # Not a valid brace expansion, return as-is
                           return [str]
                         end

            # Combine prefix, expansions, suffix and recursively expand
            results = []
            expansions.each do |exp|
              combined = "#{prefix}#{exp}#{suffix}"
              results.concat(expand_braces(combined))
            end
            return results
          end
        end
        i += 1
      end

      # No complete brace group found
      [str]
    end

    def expand_numeric_sequence(start_str, end_str, step = nil)
      start_val = start_str.to_i
      end_val = end_str.to_i

      # Check for zero-padding
      width = if start_str.start_with?('0') || start_str.start_with?('-0')
                start_str.sub(/^-/, '').length
              elsif end_str.start_with?('0') || end_str.start_with?('-0')
                end_str.sub(/^-/, '').length
              else
                0
              end

      # Determine step (use absolute value, direction is determined by start/end)
      step = step&.abs || 1
      step = 1 if step == 0  # Prevent infinite loop

      # Generate sequence
      result = []
      if start_val <= end_val
        n = start_val
        while n <= end_val
          result << n
          n += step
        end
      else
        n = start_val
        while n >= end_val
          result << n
          n -= step
        end
      end

      result.map do |n|
        if width > 0
          format("%0#{width}d", n)
        else
          n.to_s
        end
      end
    end

    def expand_letter_sequence(start_char, end_char, step = nil)
      step = step&.abs || 1
      step = 1 if step == 0  # Prevent infinite loop

      result = []
      if start_char <= end_char
        c = start_char
        while c <= end_char
          result << c
          c = (c.ord + step).chr
        end
      else
        c = start_char
        while c >= end_char
          result << c
          c = (c.ord - step).chr
        end
      end
      result
    end

    def expand_brace_list(content)
      # Split on commas, but respect nested braces
      items = []
      current = +''
      depth = 0

      content.each_char do |char|
        case char
        when '{'
          depth += 1
          current << char
        when '}'
          depth -= 1
          current << char
        when ','
          if depth == 0
            items << current
            current = +''
          else
            current << char
          end
        else
          current << char
        end
      end
      items << current unless current.empty?

      # Recursively expand any nested braces in items
      items.flat_map { |item| expand_braces(item) }
    end

    # Format time output according to TIMEFORMAT variable
    # Escape sequences:
    #   %% - literal %
    #   %[p][l]R - real (elapsed) time in seconds
    #   %[p][l]U - user CPU time in seconds
    #   %[p][l]S - system CPU time in seconds
    #   %P - CPU percentage ((user + sys) / real * 100)
    # Optional modifiers:
    #   p - precision (0-3 digits after decimal, default 3)
    #   l - long format with minutes (e.g., 1m30.000s)
    def format_timeformat(fmt, real, user, sys)
      result = +''
      i = 0

      while i < fmt.length
        if fmt[i] == '%'
          i += 1
          break if i >= fmt.length

          # Check for %%
          if fmt[i] == '%'
            result << '%'
            i += 1
            next
          end

          # Parse optional precision (0-9)
          precision = 3
          if fmt[i] =~ /[0-9]/
            precision = fmt[i].to_i
            i += 1
          end

          # Parse optional 'l' for long format
          long_format = false
          if i < fmt.length && fmt[i] == 'l'
            long_format = true
            i += 1
          end

          # Parse the time specifier
          break if i >= fmt.length
          case fmt[i]
          when 'R'
            result << format_time_value(real, precision, long_format)
          when 'U'
            result << format_time_value(user, precision, long_format)
          when 'S'
            result << format_time_value(sys, precision, long_format)
          when 'P'
            # CPU percentage
            pct = real > 0 ? ((user + sys) / real * 100) : 0
            result << format("%.#{precision}f", pct)
          else
            # Unknown specifier, keep literal
            result << '%' << fmt[i]
          end
          i += 1
        elsif fmt[i] == '\\'
          # Handle escape sequences
          i += 1
          break if i >= fmt.length
          case fmt[i]
          when 'n'
            result << "\n"
          when 't'
            result << "\t"
          else
            result << fmt[i]
          end
          i += 1
        else
          result << fmt[i]
          i += 1
        end
      end

      result
    end

    def format_time_value(seconds, precision, long_format)
      if long_format
        # Long format: minutes and seconds (e.g., 1m30.000s)
        mins = (seconds / 60).to_i
        secs = seconds % 60
        if precision > 0
          format('%dm%.*fs', mins, precision, secs)
        else
          format('%dm%ds', mins, secs.to_i)
        end
      else
        # Short format: just seconds
        if precision > 0
          format('%.*f', precision, seconds)
        else
          format('%d', seconds.to_i)
        end
      end
    end

    def eval_cond_expr(parts, start_idx, end_idx)
      # Handle empty expression
      return true if start_idx >= end_idx

      tokens = parts[start_idx...end_idx]
      return true if tokens.empty?

      # Handle logical OR (lowest precedence)
      or_idx = find_logical_op(tokens, '||')
      if or_idx
        left = eval_cond_expr(tokens, 0, or_idx)
        return true if left  # Short-circuit
        return eval_cond_expr(tokens, or_idx + 1, tokens.length)
      end

      # Handle logical AND
      and_idx = find_logical_op(tokens, '&&')
      if and_idx
        left = eval_cond_expr(tokens, 0, and_idx)
        return false unless left  # Short-circuit
        return eval_cond_expr(tokens, and_idx + 1, tokens.length)
      end

      # Handle grouping with parentheses
      if tokens.first == '(' && tokens.last == ')'
        return eval_cond_expr(tokens[1...-1], 0, tokens.length - 2)
      end

      # Handle negation
      if tokens.first == '!'
        return !eval_cond_expr(tokens[1..], 0, tokens.length - 1)
      end

      # Evaluate primary expression
      eval_cond_primary(tokens)
    end

    def find_logical_op(tokens, op)
      # Find logical operator at depth 0 (not inside parens)
      depth = 0
      tokens.each_with_index do |token, i|
        case token
        when '('
          depth += 1
        when ')'
          depth -= 1
        when op
          return i if depth == 0
        end
      end
      nil
    end

    def eval_cond_primary(tokens)
      return true if tokens.empty?

      # Unary file tests: -e file, -f file, etc.
      if tokens.length == 2 && tokens[0].start_with?('-')
        return eval_unary_test(tokens[0], tokens[1])
      end

      # Unary string tests
      if tokens.length == 1
        # Non-empty string is true
        return !tokens[0].to_s.empty?
      end

      # Binary operators
      if tokens.length == 3
        left, op, right = tokens
        return eval_binary_test(left, op, right)
      end

      # More complex expressions - try to find binary operator
      if tokens.length > 3
        # Look for binary operators in the middle
        tokens.each_with_index do |token, i|
          next if i == 0 || i == tokens.length - 1
          if %w[== != =~ < > -eq -ne -lt -le -gt -ge -nt -ot -ef].include?(token)
            left = tokens[0...i].join(' ')
            right_parts = tokens[i + 1..]
            # For regex (=~), reconstruct pattern without spaces around parens
            # For glob (== !=), also reconstruct to preserve extglob patterns
            right = if token == '=~'
                      reconstruct_regex_pattern(right_parts)
                    elsif token == '==' || token == '!='
                      reconstruct_glob_pattern(right_parts)
                    else
                      right_parts.join(' ')
                    end
            return eval_binary_test(left, token, right)
          end
        end
      end

      # Default: non-empty is true
      !tokens.join.empty?
    end

    def eval_unary_test(op, arg)
      case op
      when '-z' then arg.to_s.empty?
      when '-n' then !arg.to_s.empty?
      when '-e' then File.exist?(arg)
      when '-f' then File.file?(arg)
      when '-d' then File.directory?(arg)
      when '-r' then File.readable?(arg)
      when '-w' then File.writable?(arg)
      when '-x' then File.executable?(arg)
      when '-s' then File.exist?(arg) && File.size(arg) > 0
      when '-L', '-h' then File.symlink?(arg)
      when '-b' then File.exist?(arg) && File.stat(arg).blockdev?
      when '-c' then File.exist?(arg) && File.stat(arg).chardev?
      when '-p' then File.exist?(arg) && File.stat(arg).pipe?
      when '-S' then File.exist?(arg) && File.stat(arg).socket?
      when '-t' then $stdin.tty? && arg.to_i == 0  # -t fd
      when '-O' then File.exist?(arg) && File.owned?(arg)
      when '-G' then File.exist?(arg) && File.grpowned?(arg)
      when '-N' then File.exist?(arg) && File.mtime(arg) > File.atime(arg)
      when '-v' then ENV.key?(arg) || instance_variable_defined?("@#{arg}") rescue false
      else false
      end
    rescue
      false
    end

    def eval_binary_test(left, op, right)
      case op
      # String comparison
      when '=='
        # Pattern matching: right side is a pattern
        cond_pattern_match?(left, right)
      when '!='
        !cond_pattern_match?(left, right)
      when '=~'
        # Regex matching
        cond_regex_match?(left, right)
      when '<'
        left.to_s < right.to_s
      when '>'
        left.to_s > right.to_s
      # Integer comparison
      when '-eq' then left.to_i == right.to_i
      when '-ne' then left.to_i != right.to_i
      when '-lt' then left.to_i < right.to_i
      when '-le' then left.to_i <= right.to_i
      when '-gt' then left.to_i > right.to_i
      when '-ge' then left.to_i >= right.to_i
      # File comparison
      when '-nt'
        File.exist?(left) && File.exist?(right) && File.mtime(left) > File.mtime(right)
      when '-ot'
        File.exist?(left) && File.exist?(right) && File.mtime(left) < File.mtime(right)
      when '-ef'
        File.exist?(left) && File.exist?(right) &&
          File.stat(left).dev == File.stat(right).dev &&
          File.stat(left).ino == File.stat(right).ino
      else
        false
      end
    rescue
      false
    end

    def cond_pattern_match?(string, pattern)
      # In [[ ]], == does glob pattern matching (not literal)
      # Handle extglob patterns when extglob is enabled
      if Builtins.shopt_enabled?('extglob') && has_extglob?(pattern)
        # Convert extglob pattern to regex for matching
        # extglob_to_regex returns a Regexp with anchors already included
        base_regex = extglob_to_regex(pattern)
        if Builtins.shopt_enabled?('nocasematch')
          # Rebuild regex with case-insensitive flag
          regex = Regexp.new(base_regex.source, Regexp::IGNORECASE)
        else
          regex = base_regex
        end
        !!string.match?(regex)
      else
        # Use File.fnmatch for standard glob patterns
        flags = Builtins.shopt_enabled?('nocasematch') ? File::FNM_CASEFOLD : 0
        File.fnmatch(pattern, string, File::FNM_EXTGLOB | flags)
      end
    end

    def reconstruct_regex_pattern(parts)
      # Reconstruct regex pattern from tokenized parts
      # Parentheses and regex anchors should be directly attached (no spaces)
      result = +''
      regex_special = %w[( ) ^ $ * + ? | [ ] { }]
      parts.each_with_index do |part, i|
        if regex_special.include?(part)
          # Special regex characters don't get spaces around them
          result << part
        else
          # Add space before if previous wasn't a special char and result doesn't end with one
          prev_part = i > 0 ? parts[i - 1] : nil
          needs_space = i > 0 && !result.empty? && !regex_special.include?(prev_part) &&
                        !regex_special.any? { |s| result.end_with?(s) }
          result << ' ' if needs_space
          result << part
        end
      end
      result
    end

    def reconstruct_glob_pattern(parts)
      # Reconstruct glob pattern from tokenized parts
      # For extglob patterns like @(a|b), ?(x), *(y), +(z), !(w),
      # parentheses and pipe should be directly attached (no spaces)
      result = +''
      glob_special = %w[( ) |]
      parts.each_with_index do |part, i|
        if glob_special.include?(part)
          # Special glob characters don't get spaces around them
          result << part
        else
          # Add space before if previous wasn't a special char and result doesn't end with one
          prev_part = i > 0 ? parts[i - 1] : nil
          needs_space = i > 0 && !result.empty? && !glob_special.include?(prev_part) &&
                        !glob_special.any? { |s| result.end_with?(s) }
          result << ' ' if needs_space
          result << part
        end
      end
      result
    end

    def cond_regex_match?(string, pattern)
      # =~ does regex matching, sets RUBISH_REMATCH
      flags = Builtins.shopt_enabled?('nocasematch') ? Regexp::IGNORECASE : 0
      regex = Regexp.new(pattern, flags)
      match = regex.match(string)
      if match
        # Set RUBISH_REMATCH array
        Builtins.set_array('RUBISH_REMATCH', match.to_a)
        true
      else
        Builtins.set_array('RUBISH_REMATCH', [])
        false
      end
    rescue RegexpError
      false
    end

    def expand_heredoc_content(content)
      # Expand variables in heredoc content
      expand_string_content(content)
    end

    def find_heredoc(ast)
      case ast
      when AST::Heredoc
        ast
      when AST::Redirect
        find_heredoc(ast.command)
      when AST::Pipeline
        ast.commands.each do |cmd|
          if (h = find_heredoc(cmd))
            return h
          end
        end
        nil
      when AST::List
        ast.commands.each do |cmd|
          if (h = find_heredoc(cmd))
            return h
          end
        end
        nil
      else
        nil
      end
    end

    def collect_heredoc_content(delimiter, strip_tabs)
      lines = []
      loop do
        line = Reline.readline('> ', false)
        break unless line

        # Check for delimiter (possibly with leading tabs if strip_tabs)
        check_line = strip_tabs ? line.sub(/\A\t+/, '') : line
        if check_line.chomp == delimiter
          break
        end

        lines << line
      end
      lines.join("\n") + (lines.empty? ? '' : "\n")
    end

    def run_err_trap_if_failed
      Builtins.err_trap if @last_status != 0
    end

    # Handle exec builtin with special support for redirections
    # exec with no command but with redirections modifies shell's own FDs
    # exec with a command replaces the shell process
    def handle_exec_command(cmd)
      has_redirections = cmd.stdin || cmd.stdout || cmd.stderr

      if cmd.args.empty? && has_redirections
        # exec with only redirections - modify shell's FDs permanently
        apply_exec_redirections(cmd)
        @last_status = 0
      elsif cmd.args.empty? && !has_redirections
        # exec with no args and no redirections - just succeed
        @last_status = 0
      else
        # exec with a command - need to apply redirections then exec
        if has_redirections
          # Apply redirections before exec
          apply_exec_redirections(cmd)
        end
        # Run exec builtin (which will replace the process)
        success = Builtins.run('exec', cmd.args)
        @last_status = success ? 0 : 1
        run_err_trap_if_failed
      end
    end

    # Apply exec redirections to the current shell permanently
    def apply_exec_redirections(cmd)
      # Store original FDs if not already saved (for potential restore)
      @original_stdin ||= $stdin.dup
      @original_stdout ||= $stdout.dup
      @original_stderr ||= $stderr.dup

      # Apply redirections permanently to the shell
      # Use the file path from the File object for reopening
      if cmd.stdin
        path = cmd.stdin.respond_to?(:path) ? cmd.stdin.path : cmd.stdin.to_s
        mode = cmd.stdin.respond_to?(:internal_encoding) ? 'r' : 'r'
        $stdin.reopen(path, mode)
        cmd.stdin.close unless cmd.stdin.closed?
        @shell_stdin = path
      end

      if cmd.stdout
        path = cmd.stdout.respond_to?(:path) ? cmd.stdout.path : cmd.stdout.to_s
        # Check if append mode
        mode = cmd.stdout.respond_to?(:stat) && cmd.stdout.stat.size > 0 ? 'a' : 'w'
        $stdout.reopen(path, mode)
        cmd.stdout.close unless cmd.stdout.closed?
        @shell_stdout = path
      end

      if cmd.stderr
        path = cmd.stderr.respond_to?(:path) ? cmd.stderr.path : cmd.stderr.to_s
        mode = 'w'
        $stderr.reopen(path, mode)
        cmd.stderr.close unless cmd.stderr.closed?
        @shell_stderr = path
      end
    end
  end
end
