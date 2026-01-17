# frozen_string_literal: true

module Rubish
  class NounsetError < StandardError; end
  class FailglobError < StandardError; end

  class REPL
    # Class-level prompt configuration (fish-style)
    # Set via `def rubish_prompt` and `def rubish_right_prompt` in config
    class << self
      attr_accessor :prompt_proc, :right_prompt_proc
    end

    def initialize(login_shell: false, no_profile: false, no_rc: false, restricted: false, rcfile: nil)
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
      Builtins.set_shell_option('login_shell', login_shell)
      # SHLVL - shell nesting level (stored in ENV for inheritance)
      current_shlvl = ENV['SHLVL'].to_i
      ENV['SHLVL'] = (current_shlvl + 1).to_s
      # SHELL - full pathname of the shell
      # Set to the rubish binary path if not already set or if running rubish
      set_shell_variable
      Builtins.executor = ->(line) { execute(line) }
      Builtins.script_name_getter = -> { @script_name }
      Builtins.script_name_setter = ->(name) { @script_name = name }
      Builtins.positional_params_getter = -> { @positional_params }
      Builtins.positional_params_setter = ->(params) { @positional_params = params }
      Builtins.function_checker = ->(name) { @functions.key?(name) }
      Builtins.function_remover = ->(name) { @functions.delete(name) }
      Builtins.function_lister = -> { @functions.transform_values { |v| {source: v[:source_code], file: v[:source], lineno: v[:lineno]} } }
      Builtins.function_getter = ->(name) { f = @functions[name]; f ? {source: f[:source_code], file: f[:source], lineno: f[:lineno]} : nil }
      Builtins.heredoc_content_setter = ->(content) { @heredoc_content = content }
      Builtins.command_executor = ->(args) { execute_command_directly(args) }
      Builtins.source_file_getter = -> { @current_source_file }
      Builtins.source_file_setter = ->(file) { @current_source_file = file }
      Builtins.lineno_getter = -> { @lineno }
      Builtins.bash_argv0_unsetter = -> { @bash_argv0_unset = true }
      # Readline state callbacks
      Builtins.readline_line_getter = -> { @readline_line }
      Builtins.readline_line_setter = ->(line) { @readline_line = line }
      Builtins.readline_point_getter = -> { @readline_point }
      Builtins.readline_point_setter = ->(point) { @readline_point = point }
      Builtins.readline_mark_getter = -> { @readline_mark }
      Builtins.readline_mark_setter = ->(mark) { @readline_mark = mark }
      # bind -x executor: execute shell commands from key bindings
      Builtins.bind_x_executor = ->(command) { execute_bind_x_command(command) }
      # History callbacks
      Builtins.history_file_getter = -> { history_file }
      Builtins.history_loader = -> { load_history }
      Builtins.history_saver = -> { save_history }
      Builtins.history_appender = -> { append_history }
      # Set up Command class to handle functions in pipelines
      Command.function_checker = ->(name) { @functions.key?(name) }
      Command.function_caller = ->(name, args) { call_function(name, args) }
      # Set up Builtins to call functions (for compgen -F)
      Builtins.function_caller = ->(name, args) { call_function(name, args) }
      # Source executor for autoload: source a file or execute code string
      Builtins.source_executor = ->(file, code = nil) {
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
      exit_code = catch(:exit) do
        loop { process_line }
      end
      save_history
      load_logout_config
      exit_code
    end

    private

    def setup_reline
      Reline.completion_proc = ->(input) { complete(input) }
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

    # Load readline/Reline configuration from inputrc file
    # INPUTRC: path to the inputrc file (default: ~/.inputrc)
    def load_inputrc
      # Reline automatically checks INPUTRC env var, ~/.inputrc, and XDG paths
      # We explicitly call read to ensure it's loaded at startup
      begin
        Reline.config.read
      rescue => e
        # Silently ignore errors reading inputrc (like readline does)
        $stderr.puts "rubish: warning: #{inputrc_path}: #{e.message}" if ENV['RUBISH_DEBUG']
      end
    end

    # Get the inputrc file path that would be used
    def inputrc_path
      inputrc = ENV['INPUTRC']
      return inputrc if inputrc && !inputrc.empty? && File.exist?(inputrc)

      home_inputrc = File.expand_path('~/.inputrc')
      return home_inputrc if File.exist?(home_inputrc)

      xdg_config = ENV['XDG_CONFIG_HOME'] || File.expand_path('~/.config')
      xdg_inputrc = File.join(xdg_config, 'readline', 'inputrc')
      return xdg_inputrc if File.exist?(xdg_inputrc)

      nil
    end

    # Set the SHELL environment variable to the rubish binary path
    # SHELL: full pathname of the shell (used by subprocesses to spawn shells)
    def set_shell_variable
      # Try to find the rubish binary
      rubish_path = find_rubish_path
      return unless rubish_path

      # Set SHELL to rubish path
      ENV['SHELL'] = rubish_path
    end

    # Find the full path to the rubish binary
    def find_rubish_path
      # First, check if $0 points to rubish
      if $0 && File.basename($0) == 'rubish'
        path = File.expand_path($0)
        return path if File.executable?(path)
      end

      # Check if there's a rubish in the project's bin directory
      # __FILE__ is .../lib/rubish/repl.rb, go up 3 levels to project root
      project_root = File.dirname(File.dirname(File.dirname(__FILE__)))
      bin_rubish = File.join(project_root, 'bin', 'rubish')
      return bin_rubish if File.executable?(bin_rubish)

      # Search in PATH
      path_dirs = (ENV['PATH'] || '').split(File::PATH_SEPARATOR)
      path_dirs.each do |dir|
        rubish = File.join(dir, 'rubish')
        return rubish if File.executable?(rubish)
      end

      nil
    end

    # Get the history file path from HISTFILE or default
    def history_file
      ENV['HISTFILE'] || File.expand_path('~/.rubish_history')
    end

    # Get HISTSIZE (max entries in memory), default 500
    def histsize
      size = ENV['HISTSIZE']
      return 500 if size.nil? || size.empty?
      size.to_i
    end

    # Get HISTFILESIZE (max lines in file), default 500
    def histfilesize
      size = ENV['HISTFILESIZE']
      return 500 if size.nil? || size.empty?
      size.to_i
    end

    # Load history from HISTFILE
    def load_history
      file = history_file
      return unless File.exist?(file)

      max_entries = histsize
      # If HISTSIZE is 0 or negative, don't load history
      return if max_entries <= 0

      begin
        lines = File.readlines(file, chomp: true)
        # Only keep the last HISTSIZE entries
        lines = lines.last(max_entries) if lines.size > max_entries
        lines.each { |line| Reline::HISTORY << line }
        # Track where we are for history -a (append)
        Builtins.last_history_line = Reline::HISTORY.size
      rescue => e
        $stderr.puts "rubish: cannot read history file: #{e.message}"
      end
    end

    # Save history to HISTFILE
    def save_history
      file = history_file
      max_lines = histfilesize

      # If HISTFILESIZE is 0 or negative, don't save history
      return if max_lines <= 0

      begin
        # Create directory if needed
        dir = File.dirname(file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        if Builtins.shopt_enabled?('histappend')
          # histappend: append new entries to history file
          history = Reline::HISTORY.to_a
          last_line = Builtins.last_history_line
          new_entries = history[last_line..]

          if new_entries && !new_entries.empty?
            File.open(file, 'a') do |f|
              new_entries.each { |line| f.puts(line) }
            end
          end

          # Truncate file if it exceeds HISTFILESIZE
          truncate_history_file(file, max_lines)
        else
          # Default: overwrite history file
          history = Reline::HISTORY.to_a
          # Only keep the last HISTFILESIZE entries
          history = history.last(max_lines) if history.size > max_lines

          File.open(file, 'w') do |f|
            history.each { |line| f.puts(line) }
          end
        end
      rescue => e
        $stderr.puts "rubish: cannot write history file: #{e.message}"
      end
    end

    # Truncate history file to max_lines if needed
    def truncate_history_file(file, max_lines)
      return unless File.exist?(file)

      lines = File.readlines(file)
      return if lines.size <= max_lines

      # Keep only the last max_lines
      File.open(file, 'w') do |f|
        lines.last(max_lines).each { |line| f.print(line) }
      end
    end

    # Append new history entries to HISTFILE (for history -a)
    def append_history
      file = history_file
      max_lines = histfilesize
      return if max_lines <= 0

      begin
        history = Reline::HISTORY.to_a
        last_line = Builtins.last_history_line
        new_entries = history[last_line..]
        return if new_entries.nil? || new_entries.empty?

        # Create directory if needed
        dir = File.dirname(file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        File.open(file, 'a') do |f|
          new_entries.each { |line| f.puts(line) }
        end

        Builtins.last_history_line = history.size
      rescue => e
        $stderr.puts "rubish: cannot append to history file: #{e.message}"
      end
    end

    # Set up job control for interactive shells
    # This puts the shell in its own process group and takes control of the terminal
    # Set up default aliases (like fish)
    # These are set before load_config so users can override in .rubishrc
    def setup_default_aliases
      # Colored ls by default (like fish)
      # -G is BSD/macOS style, --color=auto is GNU/Linux style
      if RUBY_PLATFORM =~ /darwin|bsd/i
        Builtins.aliases['ls'] ||= 'ls -G'
        Builtins.aliases['ll'] ||= 'ls -lG'
        Builtins.aliases['la'] ||= 'ls -laG'
      else
        Builtins.aliases['ls'] ||= 'ls --color=auto'
        Builtins.aliases['ll'] ||= 'ls -l --color=auto'
        Builtins.aliases['la'] ||= 'ls -la --color=auto'
      end

      # Colored grep (like fish)
      Builtins.aliases['grep'] ||= 'grep --color=auto'
    end

    def setup_job_control
      return unless $stdin.tty?

      # Get the shell's original process group
      shell_pgid = Process.getpgrp

      # If we're not the process group leader, become one
      # This is needed when rubish is started from another shell
      if shell_pgid != Process.pid
        # Ignore SIGTTOU while we set up job control (we might be in background)
        old_ttou = trap('TTOU', 'IGNORE')

        begin
          # Put ourselves in our own process group
          Process.setpgid(0, 0)

          # Take control of the terminal
          Terminal.set_foreground(Process.pid) if defined?(Terminal)
        rescue Errno::EPERM
          # Can't become process group leader (e.g., already a session leader)
        ensure
          trap('TTOU', old_ttou || 'DEFAULT')
        end
      end

      # Save our process group for later use
      @shell_pgid = Process.getpgrp
    end

    def setup_signals
      # Ignore SIGINT and SIGTSTP in the shell itself
      # They should only affect foreground jobs
      trap('INT') { }        # Ignore Ctrl+C for shell (child will get it)
      trap('TSTP') { }       # Ignore Ctrl+Z for shell
      trap('TTIN') { }       # Ignore background read attempts
      trap('TTOU') { }       # Ignore background write attempts

      # SIGCHLD handler for immediate job notification when set -b is enabled
      trap('CHLD') do
        if Builtins.set_option?('b')
          JobManager.instance.check_background_jobs
        end
      end
    end

    def load_config
      # privileged mode: don't read startup files
      return if Builtins.set_option?('p')

      if @login_shell
        load_login_config
      else
        load_interactive_config
      end
    end

    # Load startup files for login shells
    # Rubish-specific files are tried first, falling back to bash files for compatibility
    # Order: /etc/profile, then rubish config (~/.config/rubish/profile or ~/.rubish_profile),
    # or fall back to bash (~/.bash_profile, ~/.bash_login, ~/.profile)
    def load_login_config
      return if @no_profile

      # System-wide profile
      source_if_exists('/etc/profile')

      # Try rubish-specific profile first
      xdg_profile = File.join(xdg_config_dir, 'profile')
      rubish_profile = File.expand_path('~/.rubish_profile')

      if File.exist?(xdg_profile) || File.exist?(rubish_profile)
        # Use rubish-specific profiles
        source_if_exists(xdg_profile)
        source_if_exists(rubish_profile)
      else
        # Fall back to bash profile files for compatibility
        profile_files = [
          File.expand_path('~/.bash_profile'),
          File.expand_path('~/.bash_login'),
          File.expand_path('~/.profile')
        ]

        profile_files.each do |profile|
          if File.exist?(profile)
            source_if_exists(profile)
            break  # Only source the first one found
          end
        end
      end
    end

    # Load startup files for interactive non-login shells
    # Rubish-specific files are tried first, falling back to bash files for compatibility
    # Order: ENV file first, then rubish config (~/.config/rubish/config or ~/.rubishrc),
    # or fall back to bash (~/.bashrc), finally local ./.rubishrc
    def load_interactive_config
      return if @no_rc

      # If --rcfile is specified, use only that file (replaces all rc files)
      if @rcfile
        source_if_exists(File.expand_path(@rcfile))
        return
      end

      # Source ENV file first if set (POSIX-style startup file for interactive shells)
      env_file = ENV['ENV']
      if env_file && !env_file.empty?
        source_if_exists(File.expand_path(env_file))
      end

      # Try rubish-specific config first
      xdg_config = File.join(xdg_config_dir, 'config')
      rubishrc = File.expand_path('~/.rubishrc')

      if File.exist?(xdg_config) || File.exist?(rubishrc)
        # Use rubish-specific config
        source_if_exists(xdg_config)
        source_if_exists(rubishrc)
      else
        # Fall back to bash config for compatibility
        source_if_exists('/etc/bash.bashrc') || source_if_exists('/etc/bashrc')
        source_if_exists(File.expand_path('~/.bashrc'))
      end

      # Source local .rubishrc in current directory (project-specific config)
      local_rubishrc = File.expand_path('./.rubishrc')
      if local_rubishrc != rubishrc  # Skip if we're already in home dir
        source_if_exists(local_rubishrc)
      end
    end

    # Load logout files for login shells
    # Rubish-specific files are tried first, falling back to bash files for compatibility
    def load_logout_config
      return unless @login_shell

      # Try rubish-specific logout first
      xdg_logout = File.join(xdg_config_dir, 'logout')
      rubish_logout = File.expand_path('~/.rubish_logout')

      if File.exist?(xdg_logout) || File.exist?(rubish_logout)
        # Use rubish-specific logout
        source_if_exists(xdg_logout)
        source_if_exists(rubish_logout)
      else
        # Fall back to bash logout for compatibility
        source_if_exists(File.expand_path('~/.bash_logout'))
      end
    end

    # Source a file if it exists, return true if sourced
    def source_if_exists(path)
      return false unless File.exist?(path)

      begin
        Builtins.run_source([path])
        true
      rescue SyntaxError => e
        $stderr.puts "rubish: #{path}: #{e.message}"
        false
      end
    end

    # Get the XDG config directory for rubish
    # Uses $XDG_CONFIG_HOME if set, otherwise ~/.config
    def xdg_config_dir
      base = ENV['XDG_CONFIG_HOME']
      if base && !base.empty?
        File.join(base, 'rubish')
      else
        File.expand_path('~/.config/rubish')
      end
    end

    def prompt
      # First check for fish-style prompt function
      if self.class.prompt_proc
        begin
          return instance_exec(&self.class.prompt_proc)
        rescue => e
          $stderr.puts "rubish: prompt error: #{e.message}"
        end
      end

      # Fall back to bash/zsh-style environment variables
      ps1 = ENV['PS1'] || ENV['PROMPT']
      if ps1
        expand_prompt(ps1)
      else
        # Default prompt
        "#{Dir.pwd.sub(ENV['HOME'], '~')}$ "
      end
    end

    def continuation_prompt
      ps2 = ENV['PS2']
      if ps2
        expand_prompt(ps2)
      else
        '> '
      end
    end

    # Right prompt (like zsh's RPROMPT)
    def right_prompt
      # First check for fish-style right prompt function
      if self.class.right_prompt_proc
        begin
          result = instance_exec(&self.class.right_prompt_proc)
          return result unless result.nil? || result.empty?
        rescue => e
          $stderr.puts "rubish: right_prompt error: #{e.message}"
        end
      end

      # Fall back to bash/zsh-style environment variables
      rprompt = ENV['RPROMPT'] || ENV['RPS1']
      return nil unless rprompt && !rprompt.empty?

      expand_prompt(rprompt)
    end

    # Set Reline's rprompt for right-side prompt display
    def setup_rprompt
      Reline.rprompt = right_prompt
    end

    # Calculate visible length of a string (excluding ANSI escape codes)
    def visible_length(str)
      # Remove ANSI escape sequences
      str.gsub(/\e\[[0-9;]*[a-zA-Z]/, '').length
    end

    # Get terminal width
    def terminal_width
      if $stdout.tty?
        begin
          _rows, cols = $stdout.winsize
          cols
        rescue
          ENV['COLUMNS']&.to_i || 80
        end
      else
        80
      end
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

    # Update history to combine multi-line command into single entry
    def update_multiline_history(lines)
      return if lines.size <= 1
      return if Reline::HISTORY.empty?

      # Remove the first line that was already added to history
      last_idx = Reline::HISTORY.size - 1
      Reline::HISTORY.delete_at(last_idx)

      # Add the combined command
      combined = if Builtins.shopt_enabled?('lithist')
                   lines.join("\n")
                 else
                   lines.join('; ')
                 end
      Reline::HISTORY << combined
    end

    def select_prompt
      ps3 = ENV['PS3']
      if ps3
        expand_prompt(ps3)
      else
        '#? '
      end
    end

    # Print PS0 prompt (displayed after command is read, before execution)
    # PS0 supports the same escape sequences as PS1
    def print_ps0
      ps0 = ENV['PS0']
      return unless ps0 && !ps0.empty?

      print expand_prompt(ps0)
      $stdout.flush
    end

    # Execute PROMPT_COMMAND before displaying the prompt
    # PROMPT_COMMAND can be:
    #   - A single command string
    #   - Multiple commands separated by semicolons
    #   - An array of commands (PROMPT_COMMAND[0], PROMPT_COMMAND[1], etc.)
    def run_prompt_command
      # First check for PROMPT_COMMAND array
      prompt_cmds = Builtins.get_array('PROMPT_COMMAND')
      if prompt_cmds && !prompt_cmds.empty?
        prompt_cmds.each do |cmd|
          next if cmd.nil? || cmd.empty?
          execute_prompt_command(cmd)
        end
        return
      end

      # Fall back to PROMPT_COMMAND as a string
      cmd = ENV['PROMPT_COMMAND']
      return if cmd.nil? || cmd.empty?

      execute_prompt_command(cmd)
    end

    def execute_prompt_command(cmd)
      # Save current state
      saved_status = @last_status

      # Execute the command silently (don't affect $?)
      begin
        execute(cmd)
      rescue => e
        # Silently ignore errors in PROMPT_COMMAND
        $stderr.puts "rubish: PROMPT_COMMAND: #{e.message}" if Builtins.set_option?('x')
      end

      # Restore the exit status (PROMPT_COMMAND shouldn't affect $?)
      @last_status = saved_status
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

    # Add command to history based on HISTCONTROL and HISTIGNORE settings
    # HISTCONTROL values (colon-separated):
    #   ignorespace  - don't save commands starting with space
    #   ignoredups   - don't save if same as previous command
    #   ignoreboth   - ignorespace + ignoredups
    #   erasedups    - erase all previous duplicates before adding
    # HISTIGNORE: colon-separated patterns to ignore
    # Update the last history entry to include heredoc content
    # This is called after heredoc content is collected
    # cmdhist: save multi-line commands as single history entry (default on)
    # lithist: preserve newlines in multi-line history (default off)
    def update_history_with_heredoc(command_line, delimiter, heredoc_content)
      return unless Builtins.shopt_enabled?('cmdhist')
      return if Reline::HISTORY.empty?

      # Build the full command with heredoc
      full_command = if Builtins.shopt_enabled?('lithist')
                       # Preserve newlines: command\nheredoc_content\ndelimiter
                       "#{command_line}\n#{heredoc_content}#{delimiter}"
                     else
                       # Replace newlines with semicolons for the heredoc content
                       # But format it as a single line: cat <<EOF; content; EOF
                       content_lines = heredoc_content.chomp.split("\n")
                       "#{command_line} #{content_lines.join('; ')}; #{delimiter}"
                     end

      # Replace the last history entry with the full command
      last_idx = Reline::HISTORY.size - 1
      Reline::HISTORY.delete_at(last_idx)
      Reline::HISTORY << full_command
    end

    def add_to_history(line)
      return if line.empty?

      histcontrol = ENV['HISTCONTROL'] || ''
      controls = histcontrol.split(':').map(&:strip)

      # Check ignorespace / ignoreboth
      if controls.include?('ignorespace') || controls.include?('ignoreboth')
        return if line.start_with?(' ')
      end

      # Check ignoredups / ignoreboth
      if controls.include?('ignoredups') || controls.include?('ignoreboth')
        last_entry = Reline::HISTORY.to_a.last
        return if last_entry == line
      end

      # Check HISTIGNORE patterns
      if should_ignore_for_history?(line)
        return
      end

      # Handle erasedups - remove all previous occurrences
      if controls.include?('erasedups')
        # Find and remove all duplicates
        indices_to_remove = []
        Reline::HISTORY.each_with_index do |entry, i|
          indices_to_remove << i if entry == line
        end
        # Remove in reverse order to maintain correct indices
        indices_to_remove.reverse_each do |i|
          Reline::HISTORY.delete_at(i)
          Builtins.remove_history_timestamp(i)
        end
      end

      # Add to history with timestamp
      index = Reline::HISTORY.size
      Reline::HISTORY << line
      Builtins.record_history_timestamp(index)

      # Send to syslog if syslog_history is enabled
      log_to_syslog(line) if Builtins.shopt_enabled?('syslog_history')
    end

    # Log command to syslog (for syslog_history shopt)
    def log_to_syslog(command)
      Syslog.open('rubish', Syslog::LOG_PID, Syslog::LOG_USER) do |s|
        s.info('HISTORY: PID=%d UID=%d %s', Process.pid, Process.uid, command)
      end
    rescue StandardError
      # Silently ignore syslog errors
    end

    # Check if command matches any HISTIGNORE pattern
    # HISTIGNORE is colon-separated list of patterns
    # Patterns support glob-style matching (* and ?)
    # Exact patterns match the entire command line
    def should_ignore_for_history?(line)
      histignore = ENV['HISTIGNORE']
      return false if histignore.nil? || histignore.empty?

      patterns = histignore.split(':')

      patterns.any? do |pattern|
        pattern = pattern.strip
        next false if pattern.empty?

        # Convert pattern to regex for matching
        # All patterns are treated as glob patterns (even without * or ?)
        regex = glob_to_regex(pattern)
        line.match?(regex)
      end
    end

    # Convert simple glob pattern to regex for HISTIGNORE
    def glob_to_regex(pattern)
      regex_str = +'^'
      pattern.each_char do |c|
        case c
        when '*'
          regex_str << '.*'
        when '?'
          regex_str << '.'
        when '.', '^', '$', '+', '|', '(', ')', '[', ']', '{', '}', '\\'
          regex_str << '\\' << c
        else
          regex_str << c
        end
      end
      regex_str << '$'
      Regexp.new(regex_str)
    end

    # Expand PS1/PS2 escape sequences
    # Supported escapes:
    #   \a - bell (ASCII 007)
    #   \d - date in "Weekday Month Date" format
    #   \D{format} - date formatted with strftime
    #   \e - escape character (ASCII 033)
    #   \h - hostname up to first '.'
    #   \H - full hostname
    #   \j - number of jobs
    #   \l - terminal device name
    #   \n - newline
    #   \r - carriage return
    #   \s - shell name
    #   \t - time in 24-hour HH:MM:SS format
    #   \T - time in 12-hour HH:MM:SS format
    #   \@ - time in 12-hour am/pm format
    #   \A - time in 24-hour HH:MM format
    #   \u - username
    #   \v - version
    #   \V - version with patch level
    #   \w - current working directory (~ for home)
    #   \W - basename of current directory
    #   \! - history number
    #   \# - command number
    #   \$ - # for root, $ for regular user
    #   \nnn - octal ASCII character
    #   \\ - literal backslash
    #   \[ - begin non-printing characters (ignored)
    #   \] - end non-printing characters (ignored)
    def expand_prompt(ps)
      result = +''
      i = 0

      while i < ps.length
        if ps[i] == '\\'
          # Bash-style escapes: \X
          i += 1
          break if i >= ps.length

          case ps[i]
          when 'a'
            result << "\a"
          when 'd'
            result << Time.now.strftime('%a %b %d')
          when 'D'
            # \D{format} - custom strftime format
            i += 1
            if i < ps.length && ps[i] == '{'
              i += 1
              fmt_end = ps.index('}', i)
              if fmt_end
                fmt = ps[i...fmt_end]
                result << Time.now.strftime(fmt)
                i = fmt_end
              end
            else
              i -= 1  # Back up, wasn't \D{...}
              result << 'D'
            end
          when 'e'
            result << "\e"
          when 'h'
            result << Socket.gethostname.split('.').first
          when 'H'
            result << Socket.gethostname
          when 'j'
            result << JobManager.instance.active.count.to_s
          when 'l'
            result << (File.basename(`tty`.strip) rescue 'tty')
          when 'n'
            result << "\n"
          when 'r'
            result << "\r"
          when 's'
            result << 'rubish'
          when 't'
            result << Time.now.strftime('%H:%M:%S')
          when 'T'
            result << Time.now.strftime('%I:%M:%S')
          when '@'
            result << Time.now.strftime('%I:%M %p')
          when 'A'
            result << Time.now.strftime('%H:%M')
          when 'u'
            result << (ENV['USER'] || Etc.getlogin || 'user')
          when 'v'
            result << Rubish::VERSION
          when 'V'
            result << Rubish::VERSION
          when 'w'
            home = ENV['HOME'] || ''
            cwd = Dir.pwd
            display_path = home.empty? ? cwd : cwd.sub(/\A#{Regexp.escape(home)}/, '~')
            result << trim_prompt_dir(display_path)
          when 'W'
            cwd = Dir.pwd
            home = ENV['HOME'] || ''
            if cwd == home
              result << '~'
            else
              result << File.basename(cwd)
            end
          when '!'
            result << (Reline::HISTORY.length + 1).to_s
          when '#'
            result << (@command_number || 1).to_s
          when '$'
            result << (Process.uid == 0 ? '#' : '$')
          when '\\'
            result << '\\'
          when '['
            # Begin non-printing sequence (for terminal escape codes)
            # We just skip this marker
          when ']'
            # End non-printing sequence
            # We just skip this marker
          when '0', '1', '2', '3', '4', '5', '6', '7'
            # Octal character \nnn
            octal = ps[i]
            while i + 1 < ps.length && ps[i + 1] =~ /[0-7]/ && octal.length < 3
              i += 1
              octal << ps[i]
            end
            result << octal.to_i(8).chr
          else
            # Unknown escape, keep literal
            result << '\\' << ps[i]
          end
          i += 1
        elsif ps[i] == '%'
          # Zsh-style escapes: %X
          i += 1
          break if i >= ps.length

          case ps[i]
          when 'n'
            result << (ENV['USER'] || Etc.getlogin || 'user')
          when 'm'
            result << Socket.gethostname.split('.').first
          when 'M'
            result << Socket.gethostname
          when '~'
            home = ENV['HOME'] || ''
            cwd = Dir.pwd
            display_path = home.empty? ? cwd : cwd.sub(/\A#{Regexp.escape(home)}/, '~')
            result << trim_prompt_dir(display_path)
          when '/'
            result << Dir.pwd
          when 'd'
            result << Dir.pwd
          when '.'
            # %. - basename like %1~
            cwd = Dir.pwd
            home = ENV['HOME'] || ''
            result << (cwd == home ? '~' : File.basename(cwd))
          when '1', '2', '3', '4', '5', '6', '7', '8', '9'
            # %N~ - last N path components
            n = ps[i].to_i
            i += 1
            if i < ps.length && ps[i] == '~'
              home = ENV['HOME'] || ''
              cwd = Dir.pwd
              display_path = home.empty? ? cwd : cwd.sub(/\A#{Regexp.escape(home)}/, '~')
              components = display_path.split('/')
              if components.length > n
                result << components.last(n).join('/')
              else
                result << display_path
              end
            else
              i -= 1
              result << '%' << ps[i]
            end
          when 'T'
            result << Time.now.strftime('%H:%M')
          when 't', '@'
            result << Time.now.strftime('%I:%M %p')
          when '*'
            result << Time.now.strftime('%H:%M:%S')
          when 'D'
            # %D or %D{format}
            i += 1
            if i < ps.length && ps[i] == '{'
              i += 1
              fmt_end = ps.index('}', i)
              if fmt_end
                fmt = ps[i...fmt_end]
                result << Time.now.strftime(fmt)
                i = fmt_end
              end
            else
              i -= 1
              result << Time.now.strftime('%y-%m-%d')
            end
          when 'g'
            # %g - git prompt info (branch, status)
            result << git_prompt_info
          when 'p'
            # %p or %p{N} - abbreviated path (like fish's prompt_pwd)
            # N specifies expand_level (default 1)
            expand_level = 1
            if i + 1 < ps.length && ps[i + 1] == '{'
              i += 2
              level_end = ps.index('}', i)
              if level_end
                expand_level = ps[i...level_end].to_i
                expand_level = 1 if expand_level < 1
                i = level_end
              else
                i -= 2
              end
            end
            result << prompt_pwd(expand_level: expand_level)
          when 'j'
            result << JobManager.instance.active.count.to_s
          when '?'
            result << @last_status.to_s
          when '#'
            result << (Process.uid == 0 ? '#' : '%')
          when 'F'
            # %F{color} - foreground color
            i += 1
            if i < ps.length && ps[i] == '{'
              i += 1
              color_end = ps.index('}', i)
              if color_end
                color = ps[i...color_end]
                result << zsh_color_to_ansi(color, :fg)
                i = color_end
              end
            else
              i -= 1
            end
          when 'f'
            result << "\e[39m"  # Reset foreground
          when 'K'
            # %K{color} - background color
            i += 1
            if i < ps.length && ps[i] == '{'
              i += 1
              color_end = ps.index('}', i)
              if color_end
                color = ps[i...color_end]
                result << zsh_color_to_ansi(color, :bg)
                i = color_end
              end
            else
              i -= 1
            end
          when 'k'
            result << "\e[49m"  # Reset background
          when 'B'
            result << "\e[1m"   # Bold on
          when 'b'
            result << "\e[22m"  # Bold off
          when 'U'
            result << "\e[4m"   # Underline on
          when 'u'
            result << "\e[24m"  # Underline off
          when '%'
            result << '%'
          else
            # Unknown escape, keep literal
            result << '%' << ps[i]
          end
          i += 1
        else
          result << ps[i]
          i += 1
        end
      end

      # promptvars (bash) / prompt_subst (zsh): if enabled, perform variable and command substitution
      if Builtins.shopt_enabled?('promptvars') || Builtins.zsh_option_enabled?('prompt_subst')
        result = expand_string_content(result)
      end

      result
    end

    # Convert zsh color names/numbers to ANSI escape codes
    # Supports: color names (red, green, blue, etc.), 0-255 color numbers
    ZSH_COLORS = {
      'black' => 0, 'red' => 1, 'green' => 2, 'yellow' => 3,
      'blue' => 4, 'magenta' => 5, 'cyan' => 6, 'white' => 7,
      'default' => 9
    }.freeze

    def zsh_color_to_ansi(color, type)
      base = type == :fg ? 30 : 40

      if color =~ /\A\d+\z/
        num = color.to_i
        if num < 8
          "\e[#{base + num}m"
        elsif num < 16
          # Bright colors (8-15)
          "\e[#{base + 60 + (num - 8)}m"
        else
          # 256-color mode
          "\e[#{type == :fg ? 38 : 48};5;#{num}m"
        end
      elsif ZSH_COLORS.key?(color.downcase)
        "\e[#{base + ZSH_COLORS[color.downcase]}m"
      else
        ''
      end
    end

    # Abbreviated path for prompts (like fish's prompt_pwd)
    # expand_level: number of trailing path components to show in full
    # Example with ~/src/github.com/amatsuda/rubish:
    #   prompt_pwd(expand_level: 1) => "~/s/g/a/rubish"
    #   prompt_pwd(expand_level: 2) => "~/s/g/amatsuda/rubish"
    def prompt_pwd(expand_level: 1)
      home = ENV['HOME'] || ''
      cwd = Dir.pwd
      path = home.empty? ? cwd : cwd.sub(/\A#{Regexp.escape(home)}/, '~')

      components = path.split('/')
      return path if components.length <= expand_level + 1

      # Handle leading empty string from absolute path or ~
      first = components.first
      rest = components[1..]

      # Number of components to abbreviate (all except the last expand_level)
      abbrev_count = rest.length - expand_level

      abbreviated = rest.take(abbrev_count).map { |c| c[0] || c }
      full = rest.drop(abbrev_count)

      ([first] + abbreviated + full).join('/')
    end

    # Color helper methods for fish-style prompts
    # These wrap text in ANSI escape codes for colorized output
    #
    # Usage in def rubish_prompt:
    #   def rubish_prompt
    #     cyan(prompt_pwd) + " " + green(git_prompt_info) + "> "
    #   end

    def black(text);   "\e[30m#{text}\e[39m"; end
    def red(text);     "\e[31m#{text}\e[39m"; end
    def green(text);   "\e[32m#{text}\e[39m"; end
    def yellow(text);  "\e[33m#{text}\e[39m"; end
    def blue(text);    "\e[34m#{text}\e[39m"; end
    def magenta(text); "\e[35m#{text}\e[39m"; end
    def cyan(text);    "\e[36m#{text}\e[39m"; end
    def white(text);   "\e[37m#{text}\e[39m"; end

    # Bright/bold colors
    def bright_black(text);   "\e[90m#{text}\e[39m"; end
    def bright_red(text);     "\e[91m#{text}\e[39m"; end
    def bright_green(text);   "\e[92m#{text}\e[39m"; end
    def bright_yellow(text);  "\e[93m#{text}\e[39m"; end
    def bright_blue(text);    "\e[94m#{text}\e[39m"; end
    def bright_magenta(text); "\e[95m#{text}\e[39m"; end
    def bright_cyan(text);    "\e[96m#{text}\e[39m"; end
    def bright_white(text);   "\e[97m#{text}\e[39m"; end

    # Text styles
    def bold(text);      "\e[1m#{text}\e[22m"; end
    def dim(text);       "\e[2m#{text}\e[22m"; end
    def italic(text);    "\e[3m#{text}\e[23m"; end
    def underline(text); "\e[4m#{text}\e[24m"; end

    # Flexible color by name or number (0-255)
    def fg(color, text)
      code = color_to_code(color, :fg)
      "#{code}#{text}\e[39m"
    end

    def bg(color, text)
      code = color_to_code(color, :bg)
      "#{code}#{text}\e[49m"
    end

    # Helper: hostname for prompts
    def hostname(short: true)
      short ? Socket.gethostname.split('.').first : Socket.gethostname
    end

    # Helper: username for prompts
    def username
      ENV['USER'] || Etc.getlogin || 'user'
    end

    # Helper: last command exit status
    def last_status
      @last_status
    end

    # Helper: current time formatted
    def prompt_time(format = '%H:%M:%S')
      Time.now.strftime(format)
    end

    private

    def color_to_code(color, type)
      base = type == :fg ? 30 : 40

      case color
      when Integer
        if color < 8
          "\e[#{base + color}m"
        elsif color < 16
          "\e[#{base + 60 + (color - 8)}m"
        else
          "\e[#{type == :fg ? 38 : 48};5;#{color}m"
        end
      when Symbol, String
        name = color.to_s.downcase
        if ZSH_COLORS.key?(name)
          "\e[#{base + ZSH_COLORS[name]}m"
        else
          ''
        end
      else
        ''
      end
    end

    public

    # Git prompt info - returns formatted git status for use in prompts
    # Configurable via environment variables:
    #   GIT_PS1_SHOWDIRTYSTATE     - show * for unstaged, + for staged changes
    #   GIT_PS1_SHOWSTASHSTATE     - show $ if stash is not empty
    #   GIT_PS1_SHOWUNTRACKEDFILES - show % if there are untracked files
    #   GIT_PS1_SHOWUPSTREAM       - show <, >, <>, = for behind, ahead, diverged, up-to-date
    #   GIT_PS1_SHOWCOLORHINTS     - colorize the output
    #   GIT_PS1_DESCRIBE_STYLE     - how to show detached HEAD (contains, branch, describe, tag, default)
    def git_prompt_info
      # Check if we're in a git repo
      git_dir = `git rev-parse --git-dir 2>/dev/null`.chomp
      return '' if git_dir.empty?

      # Get branch name or commit
      branch = `git symbolic-ref --short HEAD 2>/dev/null`.chomp
      if branch.empty?
        # Detached HEAD - show commit or tag
        style = ENV['GIT_PS1_DESCRIBE_STYLE'] || 'default'
        branch = case style
                 when 'contains'
                   `git describe --contains HEAD 2>/dev/null`.chomp
                 when 'branch'
                   `git describe --contains --all HEAD 2>/dev/null`.chomp
                 when 'tag'
                   `git describe --tags HEAD 2>/dev/null`.chomp
                 when 'describe'
                   `git describe HEAD 2>/dev/null`.chomp
                 else
                   `git rev-parse --short HEAD 2>/dev/null`.chomp
                 end
        branch = "(#{branch})" unless branch.empty?
      end
      return '' if branch.empty?

      state = +''
      color_branch = branch

      # Show dirty state (* for unstaged, + for staged)
      if ENV['GIT_PS1_SHOWDIRTYSTATE']
        # Check for staged changes
        staged = !`git diff --cached --quiet 2>/dev/null; echo $?`.chomp.to_i.zero?
        # Check for unstaged changes
        unstaged = !`git diff --quiet 2>/dev/null; echo $?`.chomp.to_i.zero?
        state << '+' if staged
        state << '*' if unstaged
      end

      # Show stash state
      if ENV['GIT_PS1_SHOWSTASHSTATE']
        stash = `git stash list 2>/dev/null`.chomp
        state << '$' unless stash.empty?
      end

      # Show untracked files
      if ENV['GIT_PS1_SHOWUNTRACKEDFILES']
        untracked = `git ls-files --others --exclude-standard 2>/dev/null`.chomp
        state << '%' unless untracked.empty?
      end

      # Show upstream status
      upstream = ''
      if ENV['GIT_PS1_SHOWUPSTREAM']
        counts = `git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null`.chomp.split
        if counts.length == 2
          ahead, behind = counts.map(&:to_i)
          if ahead > 0 && behind > 0
            upstream = '<>'
          elsif ahead > 0
            upstream = '>'
          elsif behind > 0
            upstream = '<'
          else
            upstream = '='
          end
        end
      end

      # Format output
      state_str = state.empty? ? '' : " #{state}"
      upstream_str = upstream.empty? ? '' : upstream

      # Apply colors if enabled
      if ENV['GIT_PS1_SHOWCOLORHINTS']
        # Green for clean, red for dirty, yellow for staged only
        if state.include?('*')
          color_branch = "\e[31m#{branch}\e[0m"  # Red for unstaged changes
        elsif state.include?('+')
          color_branch = "\e[33m#{branch}\e[0m"  # Yellow for staged only
        else
          color_branch = "\e[32m#{branch}\e[0m"  # Green for clean
        end
        "(#{color_branch}#{state_str}#{upstream_str})"
      else
        "(#{branch}#{state_str}#{upstream_str})"
      end
    end

    # Trim directory path according to PROMPT_DIRTRIM
    # When PROMPT_DIRTRIM is set to N, only show last N directory components
    # with leading "..." to indicate trimming
    def trim_prompt_dir(path)
      dirtrim = ENV['PROMPT_DIRTRIM']
      return path if dirtrim.nil? || dirtrim.empty?

      trim_count = dirtrim.to_i
      return path if trim_count <= 0

      # Handle ~ prefix specially
      if path.start_with?('~')
        if path == '~'
          return path
        end
        # Remove ~ prefix, process the rest
        rest = path[1..]  # includes leading /
        rest = rest[1..] if rest.start_with?('/')  # remove leading /
        components = rest.split('/')
        if components.length <= trim_count
          return path
        end
        trimmed = components.last(trim_count).join('/')
        return '~/.../' + trimmed
      else
        # Absolute or relative path
        components = path.split('/').reject(&:empty?)
        if components.length <= trim_count
          return path
        end
        trimmed = components.last(trim_count).join('/')
        return '.../' + trimmed
      end
    end

    def process_line
      # Check for completed background jobs
      JobManager.instance.check_background_jobs

      # Check for new mail (before prompt)
      check_mail

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

      # Add to history based on HISTCONTROL and HISTIGNORE settings
      add_to_history(line)

      # histverify: check for history expansion and let user verify before executing
      if Builtins.shopt_enabled?('histverify')
        expanded_line, was_expanded, _failed = expand_history_only(line)
        if was_expanded && expanded_line
          # Pre-fill the expanded command for user to verify/edit
          Reline.pre_input_hook = -> {
            Reline.insert_text(expanded_line)
            Reline.pre_input_hook = nil  # Clear after use
          }
          return  # Don't execute, let user verify on next prompt
        end
      end

      # Print PS0 before executing command (bash 4.4+ feature)
      print_ps0

      @last_line = line
      execute(line)

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

    def execute(line)
      # verbose: print input lines as read (before any processing)
      $stderr.puts line if Builtins.set_option?('v')

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
          Builtins.run_debug_trap

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
          Builtins.run_debug_trap

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
      return true if args.empty?

      name = args.first
      cmd_args = args[1..] || []

      # Check if it's a builtin first
      if Builtins.builtin?(name)
        Builtins.run(name, cmd_args)
      else
        # Run as external command
        cmd = Command.new(name, *cmd_args)
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
        Builtins.run_return_trap

        # Restore ERR trap if we cleared it
        Builtins.restore_err_trap(saved_err_trap) if saved_err_trap

        # Restore DEBUG/RETURN traps if we cleared them
        Builtins.restore_functrace_traps(saved_functrace_traps) if saved_functrace_traps

        # Pop local scope and restore variables
        Builtins.pop_local_scope
        @positional_params = saved_params

        # Pop function name from FUNCNAME stack, line number from RUBISH_LINENO stack, source from RUBISH_SOURCE stack
        @funcname_stack.shift
        @rubish_lineno_stack.shift
        @rubish_source_stack.shift
        # Pop argument count from RUBISH_ARGC stack, and corresponding args from RUBISH_ARGV stack
        argc = @rubish_argc_stack.shift || 0
        argc.times { @rubish_argv_stack.shift }
      end
    end

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
        elsif assignment =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)=(.*)\z/
          # Regular variable assignment
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
              ENV['RUBISH_ARGV0'] = expanded_value
            else
              ENV[var_name] = expanded_value
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
            ENV[var_name] = expanded_value
          end
          # allexport: mark variable as exported when set -a is enabled
          Builtins.mark_exported(var_name) if Builtins.set_option?('a')
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
      # Parse array elements, respecting quotes
      elements = []
      current = +''
      in_single_quote = false
      in_double_quote = false
      i = 0

      while i < str.length
        char = str[i]

        if char == "'" && !in_double_quote
          in_single_quote = !in_single_quote
          current << char
        elsif char == '"' && !in_single_quote
          in_double_quote = !in_double_quote
          current << char
        elsif char =~ /\s/ && !in_single_quote && !in_double_quote
          unless current.empty?
            elements << expand_assignment_value(current)
            current = +''
          end
        else
          current << char
        end
        i += 1
      end

      elements << expand_assignment_value(current) unless current.empty?
      elements
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

      if Builtins.set_option?('u') && !ENV.key?(var_name)
        $stderr.puts Builtins.format_error('unbound variable', command: var_name)
        raise NounsetError, "#{var_name}: unbound variable"
      end
      ENV.fetch(var_name, '')
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

    # Check for history expansion without side effects (for histverify)
    def expand_history_only(line)
      # Capture any output to suppress it during verification check
      original_stdout = $stdout
      $stdout = StringIO.new
      begin
        expand_history(line)
      ensure
        $stdout = original_stdout
      end
    end

    def expand_history(line)
      # History expansion with word designators and modifiers
      # Format: !event[:word][:modifier...]
      # Returns [expanded_line, was_expanded, failed]
      # If histexpand (set -H) is disabled, don't expand history
      return [line, false, false] unless Builtins.set_option?('H')
      # Don't expand history in sourced files (bash behavior)
      return [line, false, false] if Builtins.sourcing_file
      return [line, false, false] unless line.include?('!') || line.start_with?('^')

      history = Reline::HISTORY.to_a
      return [line, false, false] if history.empty?

      result = +''
      i = 0
      expanded = false
      print_only = false
      in_single_quotes = false
      in_double_quotes = false

      while i < line.length
        char = line[i]

        # Track quote state - no expansion in single quotes
        if char == "'" && !in_double_quotes
          in_single_quotes = !in_single_quotes
          result << char
          i += 1
          next
        elsif char == '"' && !in_single_quotes
          in_double_quotes = !in_double_quotes
          result << char
          i += 1
          next
        end

        # Quick substitution: ^old^new^
        if i == 0 && char == '^' && !in_single_quotes
          if line =~ /\A\^([^^]*)\^([^^]*)\^?/
            old_str = $1
            new_str = $2
            last_cmd = history[-1]
            if last_cmd&.include?(old_str)
              return [last_cmd.sub(old_str, new_str), true, false]
            else
              puts 'rubish: substitution failed'
              return [nil, false, true]
            end
          end
        end

        if char == '!' && !in_single_quotes
          expansion, consumed, error, is_print_only = parse_history_expansion(line, i, history)
          if error
            puts error
            return [nil, false, true]
          end
          if expansion
            result << expansion
            expanded = true
            print_only ||= is_print_only
            i += consumed
          else
            result << '!'
            i += 1
          end
        else
          result << char
          i += 1
        end
      end

      # If :p modifier was used, print but don't execute
      if print_only
        puts result
        return [nil, false, false]
      end

      [result, expanded, false]
    end

    def parse_history_expansion(line, pos, history)
      # Parse history expansion starting at pos
      # Returns [expansion, chars_consumed, error_message, print_only]
      i = pos + 1  # skip !
      return [nil, 0, nil, false] if i >= line.length

      # Parse event designator
      event_cmd, event_len, error = parse_event_designator(line, i, history)
      return [nil, 0, error, false] if error
      return [nil, 0, nil, false] unless event_cmd

      i += event_len
      args = parse_command_args(event_cmd)

      # Check for word designator
      selected_words = args  # default: all words
      if i < line.length && line[i] == ':'
        # Could be word designator or modifier
        word_result, word_len = parse_word_designator(line, i + 1, args)
        if word_result
          selected_words = word_result
          i += 1 + word_len
        end
      end

      # Check for modifiers
      result_text = selected_words.join(' ')
      print_only = false

      while i < line.length && line[i] == ':'
        modifier, mod_len, mod_error = parse_modifier(line, i + 1, result_text)
        break unless modifier || mod_error
        if mod_error
          return [nil, 0, mod_error, false]
        end
        if modifier == :print_only
          print_only = true
          i += 1 + mod_len
        else
          result_text = modifier
          i += 1 + mod_len
        end
      end

      [result_text, i - pos, nil, print_only]
    end

    def parse_event_designator(line, pos, history)
      # Returns [command, chars_consumed, error]
      return [nil, 0, nil] if pos >= line.length

      char = line[pos]

      case char
      when '!'
        # !! - last command
        [history[-1], 1, nil]
      when '$'
        # !$ - last argument (shorthand, no word designator needed)
        args = parse_command_args(history[-1] || '')
        [args.last || '', 1, nil]
      when '^'
        # !^ - first argument
        args = parse_command_args(history[-1] || '')
        [args[1] || '', 1, nil]
      when '*'
        # !* - all arguments
        args = parse_command_args(history[-1] || '')
        [args[1..].join(' '), 1, nil]
      when '-'
        # !-n - nth previous command
        if line[pos + 1..] =~ /\A(\d+)/
          n = $1.to_i
          cmd = history[-n]
          if cmd
            [cmd, 1 + $1.length, nil]
          else
            [nil, 0, "rubish: !-#{n}: event not found"]
          end
        else
          [nil, 0, nil]
        end
      when /\d/
        # !n - command number n
        if line[pos..] =~ /\A(\d+)/
          n = $1.to_i
          cmd = history[n - 1]
          if cmd
            [cmd, $1.length, nil]
          else
            [nil, 0, "rubish: !#{n}: event not found"]
          end
        else
          [nil, 0, nil]
        end
      when '?'
        # !?string - contains string
        if line[pos + 1..] =~ /\A([^?\s:]+)\??/
          search = $1
          cmd = history.reverse.find { |c| c.include?(search) }
          if cmd
            consumed = 1 + search.length
            consumed += 1 if line[pos + consumed] == '?'
            [cmd, consumed, nil]
          else
            [nil, 0, "rubish: !?#{search}: event not found"]
          end
        else
          [nil, 0, nil]
        end
      when /[a-zA-Z]/
        # !string - starts with string
        if line[pos..] =~ /\A([a-zA-Z][^\s:]*)/
          search = $1
          cmd = history.reverse.find { |c| c.start_with?(search) }
          if cmd
            [cmd, search.length, nil]
          else
            [nil, 0, "rubish: !#{search}: event not found"]
          end
        else
          [nil, 0, nil]
        end
      when ' ', "\t", nil
        [nil, 0, nil]
      else
        [nil, 0, nil]
      end
    end

    def parse_word_designator(line, pos, args)
      # Returns [selected_words_array, chars_consumed] or [nil, 0]
      return [nil, 0] if pos >= line.length

      case line[pos]
      when '0'
        # :0 - command name
        [[args[0] || ''], 1]
      when '^'
        # :^ - first argument
        [[args[1] || ''], 1]
      when '$'
        # :$ - last argument
        [[args.last || ''], 1]
      when '*'
        # :* - all arguments
        [args[1..] || [], 1]
      when '-'
        # :-n - from 0 to n
        if line[pos + 1..] =~ /\A(\d+)/
          end_n = $1.to_i
          [args[0..end_n] || [], 1 + $1.length]
        else
          [nil, 0]
        end
      when /\d/
        # :n or :n-m or :n-$ or :n* or :n-
        if line[pos..] =~ /\A(\d+)(-(\d+|\$|\*)?|\*)?/
          start_n = $1.to_i
          range_part = $2
          consumed = $1.length + (range_part&.length || 0)

          if range_part.nil?
            # Just :n
            [[args[start_n] || ''], consumed]
          elsif range_part == '*'
            # :n* - from n to end
            [args[start_n..] || [], consumed]
          elsif range_part == '-'
            # :n- - from n to last-1
            [args[start_n...-1] || [], consumed]
          elsif range_part.start_with?('-')
            end_part = range_part[1..]
            if end_part == '$' || end_part == '*'
              # :n-$ or :n-*
              [args[start_n..] || [], consumed]
            elsif end_part.empty?
              # :n- - from n to last-1
              [args[start_n...-1] || [], consumed]
            else
              # :n-m
              end_n = end_part.to_i
              [args[start_n..end_n] || [], consumed]
            end
          else
            [[args[start_n] || ''], $1.length]
          end
        else
          [nil, 0]
        end
      else
        [nil, 0]
      end
    end

    def parse_modifier(line, pos, text)
      # Returns [modified_text_or_symbol, chars_consumed, error]
      return [nil, 0, nil] if pos >= line.length

      case line[pos]
      when 'h'
        # :h - head (dirname)
        [File.dirname(text), 1, nil]
      when 't'
        # :t - tail (basename)
        [File.basename(text), 1, nil]
      when 'r'
        # :r - remove extension
        ext = File.extname(text)
        [ext.empty? ? text : text[0...-ext.length], 1, nil]
      when 'e'
        # :e - extension only
        ext = File.extname(text)
        [ext.empty? ? '' : ext[1..], 1, nil]
      when 'p'
        # :p - print only, don't execute
        [:print_only, 1, nil]
      when 'q'
        # :q - quote the text
        [Shellwords.escape(text), 1, nil]
      when 's', 'g'
        # :s/old/new/ or :gs/old/new/ - substitute
        global = line[pos] == 'g'
        start = global ? pos + 1 : pos
        return [nil, 0, nil] unless start < line.length && line[start] == 's'
        return [nil, 0, nil] unless start + 1 < line.length

        delimiter = line[start + 1]
        return [nil, 0, nil] unless delimiter && delimiter =~ /[\/^]/

        # Find old_str (between first and second delimiter)
        old_start = start + 2
        old_end = line.index(delimiter, old_start)
        return [nil, 0, 'rubish: bad substitution'] unless old_end

        old_str = line[old_start...old_end]

        # Find new_str (between second and optional third delimiter)
        new_start = old_end + 1
        new_end = line.index(delimiter, new_start) || line.length
        # Check if new_end is followed by word boundary or modifier
        if new_end < line.length && line[new_end] == delimiter
          new_str = line[new_start...new_end]
          consumed = new_end - pos + 1  # include trailing delimiter
        else
          # No trailing delimiter, find end of word
          new_end = new_start
          while new_end < line.length && line[new_end] !~ /[\s:]/
            new_end += 1
          end
          new_str = line[new_start...new_end]
          consumed = new_end - pos
        end

        if global
          [text.gsub(old_str, new_str), consumed, nil]
        else
          [text.sub(old_str, new_str), consumed, nil]
        end
      when '&'
        # :& - repeat last substitution (not implemented, skip)
        [nil, 0, nil]
      else
        [nil, 0, nil]
      end
    end

    def parse_command_args(cmd)
      # Simple tokenization for history expansion
      # Handles quoted strings
      args = []
      current = +''
      in_single = false
      in_double = false
      i = 0

      while i < cmd.length
        char = cmd[i]
        if char == "'" && !in_double
          in_single = !in_single
          current << char
        elsif char == '"' && !in_single
          in_double = !in_double
          current << char
        elsif char =~ /\s/ && !in_single && !in_double
          args << current unless current.empty?
          current = +''
        else
          current << char
        end
        i += 1
      end
      args << current unless current.empty?
      args
    end

    def eval_in_context(code)
      result = binding.eval(code)
      if result.is_a?(Command) && result.name == 'exec'
        # Don't auto-run exec - it's handled specially in execute method
        # to support redirections without command replacement
        result
      elsif result.is_a?(Command) && @functions.key?(result.name)
        # Call user-defined function, handling redirects
        call_function_with_redirects(result)
        @pipestatus = [@last_status]
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
        trap('INT', 'DEFAULT')
        trap('TSTP', 'DEFAULT')

        # Create new process group if job control is enabled
        Process.setpgid(0, 0) if Builtins.set_option?('m')

        # Execute the command
        result = block.call
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)
        exit(0)
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
      ENV[varname] = fd_num.to_s

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

    def __for_loop(variable, items, &block)
      items.each do |item|
        ENV[variable] = item
        block.call
      end
    end

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
        ENV['REPLY'] = reply

        # Parse selection
        if reply =~ /\A\d+\z/
          num = reply.to_i
          if num >= 1 && num <= items.length
            ENV[variable] = items[num - 1]
          else
            ENV[variable] = ''
          end
        else
          ENV[variable] = ''
        end

        # Execute body
        block.call
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

    def __arith(expr)
      # Evaluate arithmetic expression
      # Replace variable references with their values
      # Also handle positional parameters like $1, $2, etc.
      expanded = expr.gsub(/\$\{([^}]+)\}|\$(\d+)|\$([a-zA-Z_][a-zA-Z0-9_]*)|([a-zA-Z_][a-zA-Z0-9_]*)/) do |match|
        if $2 # Positional parameter like $1, $2
          n = $2.to_i
          (@positional_params[n - 1] || '0')
        elsif (var_name = $1 || $3 || $4)
          # Use __get_special_var for special variables, fall back to ENV
          __get_special_var(var_name) || ENV.fetch(var_name, '0')
        else
          match
        end
      end

      # Evaluate the expression safely (only allow arithmetic)
      # Convert shell operators to Ruby: ** for exponentiation is same
      # Note: bash uses ** for exponent, which Ruby also supports
      begin
        result = eval(expanded)
        result.to_s
      rescue StandardError
        '0'
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
      return Builtins.bashopts if var_name == 'BASHOPTS'
      return Builtins.bash_compat if var_name == 'BASH_COMPAT'
      return ENV['RUBISH_EXECUTION_STRING'] || '' if var_name == 'RUBISH_EXECUTION_STRING' || var_name == 'BASH_EXECUTION_STRING'
      return __rubish_path if var_name == 'RUBISH' || var_name == 'BASH'
      return Builtins.current_trapsig || '' if var_name == 'RUBISH_TRAPSIG' || var_name == 'BASH_TRAPSIG'
      return Builtins.readline_line if var_name == 'READLINE_LINE'
      return Builtins.readline_point.to_s if var_name == 'READLINE_POINT'
      return Builtins.readline_mark.to_s if var_name == 'READLINE_MARK'

      # Check if it's an array variable - join with space for string context
      if Builtins.array?(var_name)
        return Builtins.get_array(var_name).join(' ')
      end

      # Fetch variable with nounset check
      if Builtins.set_option?('u') && !ENV.key?(var_name)
        $stderr.puts Builtins.format_error('unbound variable', command: var_name)
        raise NounsetError, "#{var_name}: unbound variable"
      end
      ENV.fetch(var_name, '')
    end

    # Fetch variable for use as command argument
    # Returns array if variable is an array (for proper expansion)
    # Returns string otherwise
    def __fetch_var_for_arg(var_name)
      # Check if it's an array variable first
      if Builtins.array?(var_name)
        return Builtins.get_array(var_name)
      end

      # Otherwise fetch as regular variable
      __fetch_var(var_name)
    end

    def __run_subst(cmd)
      # Run command substitution with proper inherit_errexit handling
      # If inherit_errexit is enabled and errexit (set -e) is active,
      # run the command with errexit enabled in the subshell
      if Builtins.shopt_enabled?('inherit_errexit') && Builtins.set_option?('e')
        # Prefix with set -e so the subshell inherits errexit
        output = `set -e; #{cmd}`.chomp
      else
        output = `#{cmd}`.chomp
      end
      # Update @last_status with the command substitution's exit status
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
          value = ENV[var_name]
          is_set = ENV.key?(var_name)
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
      else
        value = ENV[var_name]
        is_set = ENV.key?(var_name)
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
            ENV[var_name] = operand
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
            ENV[var_name] = operand
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
      value = __get_special_var(var_name) || ENV[var_name] || ''
      value.length.to_s
    end

    def __param_substring(var_name, offset, length)
      # ${var:offset} or ${var:offset:length}
      value = __get_special_var(var_name) || ENV[var_name] || ''
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
      value = __get_special_var(var_name) || ENV[var_name]

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
      value = __get_special_var(var_name) || ENV[var_name] || ''
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
      value = ENV[var_name] || ''
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
      indirect_name = ENV[var_name]
      return '' if indirect_name.nil? || indirect_name.empty?
      ENV[indirect_name] || ''
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
      ENV.key?('RUBISH_ARGV0') ? ENV['RUBISH_ARGV0'] : @script_name
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
      expanded_index = expand_string_content(index)

      # array_expand_once (bash 5.2+): when disabled (default), subscripts may be expanded again
      # assoc_expand_once (deprecated): same but only for associative arrays
      # This allows double expansion of variables in subscripts
      expand_once = Builtins.shopt_enabled?('array_expand_once') ||
                    (Builtins.assoc_array?(var_name) && Builtins.shopt_enabled?('assoc_expand_once'))
      if (Builtins.assoc_array?(var_name) || Builtins.indexed_array?(var_name)) && !expand_once
        # Without array_expand_once, perform a second expansion if the result contains $
        if expanded_index.include?('$')
          expanded_index = expand_string_content(expanded_index)
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

    def __glob(pattern)
      # If noglob is set, return pattern as-is (no expansion)
      return [pattern] if Builtins.set_option?('f')

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

          # Execute the command via shell
          exec('/bin/sh', '-c', command)
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

          # Execute the command via shell
          exec('/bin/sh', '-c', command)
        end
        Process.detach(pid)
      end

      fifo_path
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

    def __brace(pattern)
      # Expand brace patterns like {a,b,c} or {1..5}
      # Only expand if braceexpand option is enabled
      return [pattern] unless Builtins.set_option?('B')

      expand_braces(pattern)
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
        trap('INT', 'DEFAULT')
        trap('TSTP', 'DEFAULT')

        # Execute the command
        result = block.call
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)
        exit(result.respond_to?(:success?) && result.success? ? 0 : 1)
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

    def __cond_test(parts)
      # Evaluate [[ ]] conditional expression
      # Returns ExitStatus based on expression result
      result = eval_cond_expr(parts, 0, parts.length)
      ExitStatus.new(result ? 0 : 1)
    end

    def __arithmetic_command(expr)
      # Evaluate (( )) arithmetic command
      # Returns exit status 0 if result is non-zero, 1 if result is zero
      # Supports variable assignments like x=1, x++, x--, ++x, --x, x+=1, etc.
      result = eval_arithmetic_expr(expr)
      ExitStatus.new(result != 0 ? 0 : 1)
    end

    def eval_arithmetic_expr(expr)
      # Handle comma-separated expressions (evaluate all, return last)
      # Be careful not to split inside parentheses
      expressions = split_arithmetic_expressions(expr)
      result = 0

      expressions.each do |e|
        e = e.strip
        next if e.empty?

        result = eval_single_arithmetic(e)
      end

      result
    end

    def split_arithmetic_expressions(expr)
      # Split by comma, but not inside parentheses
      result = []
      current = +''
      depth = 0

      expr.each_char do |c|
        case c
        when '('
          depth += 1
          current << c
        when ')'
          depth -= 1
          current << c
        when ','
          if depth == 0
            result << current
            current = +''
          else
            current << c
          end
        else
          current << c
        end
      end

      result << current unless current.empty?
      result
    end

    def eval_single_arithmetic(expr)
      # Handle pre-increment/decrement: ++var, --var
      if expr =~ /\A\+\+([a-zA-Z_][a-zA-Z0-9_]*)\z/
        var = $1
        val = (ENV[var] || '0').to_i + 1
        ENV[var] = val.to_s
        return val
      end

      if expr =~ /\A--([a-zA-Z_][a-zA-Z0-9_]*)\z/
        var = $1
        val = (ENV[var] || '0').to_i - 1
        ENV[var] = val.to_s
        return val
      end

      # Handle post-increment/decrement: var++, var--
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\+\+\z/
        var = $1
        old_val = (ENV[var] || '0').to_i
        ENV[var] = (old_val + 1).to_s
        return old_val
      end

      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)--\z/
        var = $1
        old_val = (ENV[var] || '0').to_i
        ENV[var] = (old_val - 1).to_s
        return old_val
      end

      # Handle compound assignments: var+=, var-=, var*=, var/=, var%=, var<<=, var>>=, var&=, var|=, var^=
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\s*(\+|-|\*|\/|%|<<|>>|&|\||\^)=\s*(.+)\z/
        var, op, rhs = $1, $2, $3
        lhs_val = (ENV[var] || '0').to_i
        rhs_val = eval_single_arithmetic(rhs)
        result = case op
                 when '+' then lhs_val + rhs_val
                 when '-' then lhs_val - rhs_val
                 when '*' then lhs_val * rhs_val
                 when '/' then rhs_val != 0 ? lhs_val / rhs_val : 0
                 when '%' then rhs_val != 0 ? lhs_val % rhs_val : 0
                 when '<<' then lhs_val << rhs_val
                 when '>>' then lhs_val >> rhs_val
                 when '&' then lhs_val & rhs_val
                 when '|' then lhs_val | rhs_val
                 when '^' then lhs_val ^ rhs_val
                 end
        ENV[var] = result.to_s
        return result
      end

      # Handle simple assignment: var=expr (but not == comparison)
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(?!=)(.+)\z/
        var, rhs = $1, $2
        result = eval_single_arithmetic(rhs)
        ENV[var] = result.to_s
        return result
      end

      # Regular arithmetic expression - evaluate directly to handle booleans
      # Expand variables first
      expanded = expr.gsub(/\$\{([^}]+)\}|\$(\d+)|\$([a-zA-Z_][a-zA-Z0-9_]*)|([a-zA-Z_][a-zA-Z0-9_]*)/) do |match|
        if $2 # Positional parameter like $1, $2
          n = $2.to_i
          (@positional_params[n - 1] || '0')
        elsif (var_name = $1 || $3 || $4)
          __get_special_var(var_name) || ENV.fetch(var_name, '0')
        else
          match
        end
      end

      begin
        result = eval(expanded)
        # Handle boolean results (comparison operators return true/false in Ruby)
        case result
        when true then 1
        when false then 0
        when Numeric then result.to_i
        else result.to_s.to_i
        end
      rescue StandardError
        0
      end
    end

    def __array_assign(var_part, elements)
      # Handle array assignment: VAR=(a b c) or VAR+=(d e)
      # var_part includes the = or +=, e.g., "arr=" or "arr+="

      # Build the assignment string and use handle_bare_assignments
      assignment_str = "#{var_part}(#{elements.join(' ')})"
      handle_bare_assignments([assignment_str])

      ExitStatus.new(0)
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

    def __define_function(name, source_code = nil, params = nil, &block)
      # Special handling for prompt functions - treat body as Ruby code
      if name == 'rubish_prompt' || name == 'rubish_right_prompt'
        define_prompt_function(name, source_code)
        return nil
      end

      @functions[name] = {block: block, source: @current_source_file, source_code: source_code, lineno: @lineno, params: params}
      nil
    end

    # Define a prompt function from Ruby code
    # The source_code is evaluated as Ruby and should return a string
    def define_prompt_function(name, source_code)
      return unless source_code

      # Extract the Ruby code from the function body
      # Remove leading/trailing whitespace and any 'end' that might be included
      code = source_code.strip

      begin
        # Create a proc that evaluates the Ruby code in REPL context
        prompt_proc = eval("-> { #{code} }")

        if name == 'rubish_prompt'
          self.class.prompt_proc = prompt_proc
        else
          self.class.right_prompt_proc = prompt_proc
        end
      rescue SyntaxError => e
        $stderr.puts "#{name}: syntax error: #{e.message}"
      rescue => e
        $stderr.puts "#{name}: error: #{e.message}"
      end
    end

    # Builtins that must run in current process (affect shell state)
    PROCESS_BUILTINS = %w[cd export set shift source . return exit break continue local unset readonly declare typeset let eval command builtin shopt alias unalias trap].freeze

    def __run_cmd(&block)
      result = block.call

      # Run DEBUG trap before each command
      Builtins.run_debug_trap

      if result.is_a?(Command) && result.name == 'exec'
        # Special handling for exec builtin
        handle_exec_command(result)
        result
      elsif result.is_a?(Command) && PROCESS_BUILTINS.include?(result.name)
        # Run process-affecting builtins directly in current process
        success = Builtins.run(result.name, result.args)
        @last_status = success ? 0 : 1
        run_err_trap_if_failed
        # Return ExitStatus to prevent eval_in_context from trying to run command again
        ExitStatus.new(@last_status)
      elsif result.is_a?(Command) && Builtins.builtin?(result.name) && !result.stdout && !result.stderr
        # Run builtins without explicit redirects in current process
        # This allows them to respect $stdout set by __with_redirect for compound commands
        success = Builtins.run(result.name, result.args)
        @last_status = success ? 0 : 1
        run_err_trap_if_failed
        # Return ExitStatus so callers (like Subshell) know the real exit status
        ExitStatus.new(@last_status)
      elsif result.is_a?(Command) && @functions.key?(result.name)
        # Call user-defined function with redirects
        call_function_with_redirects(result)
        # Don't run ERR trap here - it was already handled inside the function
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
        elsif result.respond_to?(:exitstatus)
          # Handle ExitStatus objects (from __cond_test, etc.)
          @last_status = result.exitstatus || 0
          @pipestatus = [@last_status]
          run_err_trap_if_failed
        end
        result
      end
    end

    def run_err_trap_if_failed
      Builtins.run_err_trap if @last_status != 0
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

    def complete(input)
      line = Reline.line_buffer
      point = Reline.point rescue line.length

      # no_empty_cmd_completion: do not complete on empty command line
      if Builtins.shopt_enabled?('no_empty_cmd_completion') && line.strip.empty?
        return []
      end

      # hostcomplete: attempt hostname completion when input starts with @
      if Builtins.shopt_enabled?('hostcomplete') && input.start_with?('@')
        hostname_prefix = input[1..]  # Remove the @ prefix
        hostnames = complete_hostname(hostname_prefix)
        return hostnames.map { |h| "@#{h}" } unless hostnames.empty?
      end

      # Parse command line into words
      words = split_completion_words(line)
      is_first_word = words.length <= 1

      if is_first_word
        complete_command(input)
      else
        # Check for programmable completion (only if progcomp is enabled)
        cmd = words.first
        spec = Builtins.shopt_enabled?('progcomp') ? Builtins.get_completion_spec(cmd) : nil

        if spec && spec[:function]
          # Calculate COMP_CWORD (index of word containing cursor)
          cword = calculate_comp_cword(line, point, words)

          # Set up COMP_* variables
          Builtins.set_completion_context(
            line: line,
            point: point,
            words: words,
            cword: cword,
            type: 9,  # TAB = normal completion
            key: 9    # TAB key
          )

          begin
            # Call the completion function
            # First check for builtin completion functions, then user-defined
            prev = words[cword - 1] || ''
            if Builtins.builtin_completion_function?(spec[:function])
              Builtins.call_builtin_completion_function(spec[:function], cmd, input, prev)
            else
              call_function(spec[:function], [cmd, input, prev])
            end

            # Get results from COMPREPLY array (synced from shell array for user-defined functions)
            # Shell functions modify the COMPREPLY array via set_array, so read from there
            results = Builtins.get_array('COMPREPLY').dup
            # Also check the class variable for builtin completion functions
            results = Builtins.compreply.dup if results.empty? && !Builtins.compreply.empty?

            # Apply filter pattern if specified
            if spec[:filterpat] && !results.empty?
              pattern = Regexp.new(spec[:filterpat].gsub('*', '.*').gsub('?', '.'))
              results.reject! { |r| r.match?(pattern) }
            end

            # Filter results by current input (like readline does)
            results.select! { |r| r.start_with?(input) } unless input.empty?

            # Add prefix/suffix if specified
            if spec[:prefix] || spec[:suffix]
              results.map! { |r| "#{spec[:prefix]}#{r}#{spec[:suffix]}" }
            end

            return results.uniq.sort
          ensure
            Builtins.clear_completion_context
          end
        elsif spec
          # Use spec without function (wordlist, actions, etc.)
          return Builtins.generate_completions(spec, input)
        else
          complete_file(input)
        end
      end
    end

    def split_completion_words(line)
      # Split line into words using COMP_WORDBREAKS
      # Handles: backslash escapes, quotes, $'...', $(cmd), <(cmd), >(cmd), ${var}, {a,b,c}
      wordbreaks = Builtins.comp_wordbreaks
      words = []
      current = +''
      pos = 0

      while pos < line.length
        c = line[pos]
        two_char = line[pos, 2]

        # Backslash escape - skip next character
        if c == '\\'
          current << c
          pos += 1
          if pos < line.length
            current << line[pos]
            pos += 1
          end
          next
        end

        # ANSI-C quoting: $'...'
        if two_char == "$'"
          start = pos
          pos += 2  # skip $'
          while pos < line.length
            if line[pos] == '\\'
              pos += 2  # skip escaped char
            elsif line[pos] == "'"
              pos += 1
              break
            else
              pos += 1
            end
          end
          current << line[start...pos]
          next
        end

        # Command substitution: $(...)
        if two_char == '$('
          start = pos
          pos += 2  # skip $(
          depth = 1
          while pos < line.length && depth > 0
            if line[pos] == '('
              depth += 1
            elsif line[pos] == ')'
              depth -= 1
            elsif line[pos] == '"' || line[pos] == "'"
              # Skip quoted content
              quote = line[pos]
              pos += 1
              while pos < line.length && line[pos] != quote
                pos += 2 if line[pos] == '\\'
                pos += 1
              end
            end
            pos += 1
          end
          current << line[start...pos]
          next
        end

        # Variable expansion: ${...}
        if two_char == '${'
          start = pos
          pos += 2  # skip ${
          depth = 1
          while pos < line.length && depth > 0
            if line[pos] == '{'
              depth += 1
            elsif line[pos] == '}'
              depth -= 1
            end
            pos += 1
          end
          current << line[start...pos]
          next
        end

        # Process substitution: <(...) or >(...)
        if two_char == '<(' || two_char == '>('
          start = pos
          pos += 2  # skip <( or >(
          depth = 1
          while pos < line.length && depth > 0
            if line[pos] == '('
              depth += 1
            elsif line[pos] == ')'
              depth -= 1
            elsif line[pos] == '"' || line[pos] == "'"
              quote = line[pos]
              pos += 1
              while pos < line.length && line[pos] != quote
                pos += 2 if line[pos] == '\\'
                pos += 1
              end
            end
            pos += 1
          end
          current << line[start...pos]
          next
        end

        # Brace expansion: {...}
        # Only if it looks like brace expansion (contains comma or ..)
        if c == '{' && looks_like_brace_expansion_at?(line, pos)
          start = pos
          depth = 1
          pos += 1
          while pos < line.length && depth > 0
            if line[pos] == '{'
              depth += 1
            elsif line[pos] == '}'
              depth -= 1
            end
            pos += 1
          end
          current << line[start...pos]
          next
        end

        # Double-quoted string
        if c == '"'
          current << c
          pos += 1
          while pos < line.length && line[pos] != '"'
            if line[pos] == '\\'
              current << line[pos]
              pos += 1
              if pos < line.length
                current << line[pos]
                pos += 1
              end
            else
              current << line[pos]
              pos += 1
            end
          end
          if pos < line.length
            current << line[pos]  # closing quote
            pos += 1
          end
          next
        end

        # Single-quoted string
        if c == "'"
          current << c
          pos += 1
          while pos < line.length && line[pos] != "'"
            current << line[pos]
            pos += 1
          end
          if pos < line.length
            current << line[pos]  # closing quote
            pos += 1
          end
          next
        end

        # Backtick command substitution: `...`
        if c == '`'
          start = pos
          pos += 1
          while pos < line.length
            if line[pos] == '\\'
              pos += 2
            elsif line[pos] == '`'
              pos += 1
              break
            else
              pos += 1
            end
          end
          current << line[start...pos]
          next
        end

        # Word break character
        if wordbreaks.include?(c)
          words << current unless current.empty?
          current = +''
          pos += 1
          next
        end

        # Regular character
        current << c
        pos += 1
      end

      words << current unless current.empty?
      words
    end

    def looks_like_brace_expansion_at?(line, pos)
      # Check if { at pos looks like brace expansion {a,b} or {1..5}
      # Not: variable ${var} or function body { cmd; }
      return false unless line[pos] == '{'

      depth = 1
      i = pos + 1
      has_comma = false
      has_dotdot = false

      while i < line.length && depth > 0
        case line[i]
        when '{'
          depth += 1
        when '}'
          depth -= 1
        when ','
          has_comma = true if depth == 1
        when '.'
          if line[i + 1] == '.'
            has_dotdot = true if depth == 1
            i += 1
          end
        when ' ', "\t", "\n"
          # Whitespace inside braces suggests function body, not brace expansion
          return false if depth > 0
        end
        i += 1
      end

      depth == 0 && (has_comma || has_dotdot)
    end

    def calculate_comp_cword(line, point, words)
      # Find which word the cursor is in
      pos = 0
      words.each_with_index do |word, idx|
        word_start = line.index(word, pos)
        break idx if word_start.nil?
        word_end = word_start + word.length
        return idx if point >= word_start && point <= word_end
        pos = word_end
      end
      words.length
    end

    # Complete hostnames from /etc/hosts and HOSTFILE
    def complete_hostname(prefix)
      hostnames = Set.new

      # Read from /etc/hosts
      if File.exist?('/etc/hosts')
        begin
          File.readlines('/etc/hosts').each do |line|
            # Skip comments and empty lines
            line = line.split('#').first&.strip
            next if line.nil? || line.empty?

            # Parse: IP hostname [aliases...]
            parts = line.split(/\s+/)
            next if parts.length < 2

            # Skip the IP address, collect hostnames
            parts[1..].each do |hostname|
              hostnames << hostname if hostname.start_with?(prefix)
            end
          end
        rescue Errno::EACCES, Errno::ENOENT
          # Can't read file, skip
        end
      end

      # Also read from HOSTFILE if set
      hostfile = ENV['HOSTFILE']
      if hostfile && File.exist?(hostfile)
        begin
          File.readlines(hostfile).each do |line|
            line = line.split('#').first&.strip
            next if line.nil? || line.empty?

            parts = line.split(/\s+/)
            next if parts.length < 2

            parts[1..].each do |hostname|
              hostnames << hostname if hostname.start_with?(prefix)
            end
          end
        rescue Errno::EACCES, Errno::ENOENT
          # Can't read file, skip
        end
      end

      hostnames.to_a.sort
    end

    def complete_command(input)
      results = []

      # Builtins
      Builtins::COMMANDS.each do |cmd|
        results << cmd if cmd.start_with?(input)
      end

      # User-defined functions
      @functions.keys.each do |name|
        results << name if name.start_with?(input)
      end

      # Commands from PATH
      ENV['PATH'].split(':').each do |dir|
        next unless Dir.exist?(dir)

        Dir.foreach(dir) do |file|
          next if file.start_with?('.')
          next unless file.start_with?(input)

          path = File.join(dir, file)
          results << file if File.executable?(path)
        end
      rescue Errno::EACCES
        # Skip directories we can't read
      end

      results.uniq.sort
    end

    def complete_file(input)
      # direxpand: expand directory names during word completion
      expanded_input = input
      if Builtins.shopt_enabled?('direxpand')
        expanded_input = expand_for_completion(input)
      end

      candidates = Dir.glob("#{expanded_input}*").map do |f|
        File.directory?(f) ? "#{f}/" : f
      end.sort

      # dirspell: if no matches and dirspell is enabled, try to correct directory spelling
      if candidates.empty? && Builtins.shopt_enabled?('dirspell')
        corrected = correct_completion_path(input)
        if corrected && corrected != input
          candidates = Dir.glob("#{corrected}*").map do |f|
            File.directory?(f) ? "#{f}/" : f
          end.sort
        end
      end

      # Apply FIGNORE filtering
      # force_fignore: when enabled (default), FIGNORE is always applied
      # when disabled, if only one completion remains, don't filter it out
      fignore = ENV['FIGNORE']
      if fignore && !fignore.empty?
        suffixes = fignore.split(':').reject(&:empty?)
        unless suffixes.empty?
          filtered = candidates.reject do |f|
            # Don't filter directories
            next false if f.end_with?('/')
            suffixes.any? { |suffix| f.end_with?(suffix) }
          end

          if Builtins.shopt_enabled?('force_fignore')
            # Always apply FIGNORE, even if it filters out the only match
            candidates = filtered unless filtered.empty?
          else
            # Without force_fignore, don't filter if only one candidate would remain
            # and it would be filtered out
            if filtered.empty? && candidates.length == 1
              # Keep the single candidate even though it matches FIGNORE
            else
              candidates = filtered unless filtered.empty?
            end
          end
        end
      end

      # complete_fullquote: quote shell metacharacters in completion results
      if Builtins.shopt_enabled?('complete_fullquote')
        candidates = candidates.map { |c| quote_completion_metacharacters(c) }
      end

      candidates
    end

    # Quote shell metacharacters in completion results
    # These characters need escaping to prevent shell interpretation
    SHELL_METACHARACTERS = " \t\n|&;()<>!{}$`\\\"'*?[]#~=%".chars.to_set.freeze

    def quote_completion_metacharacters(str)
      result = +''
      str.each_char do |c|
        if SHELL_METACHARACTERS.include?(c)
          result << '\\' << c
        else
          result << c
        end
      end
      result
    end

    # Expand tilde and variables for completion (direxpand)
    def expand_for_completion(input)
      result = input

      # Expand ~ at the beginning
      if result.start_with?('~')
        if result == '~' || result.start_with?('~/')
          # ~/... -> /home/user/...
          result = result.sub(/^~/, Dir.home)
        elsif result =~ /^~([^\/]+)(.*)/
          # ~username/... -> /home/username/...
          username = $1
          rest = $2
          begin
            user_home = Dir.home(username)
            result = "#{user_home}#{rest}"
          rescue ArgumentError
            # Unknown user, leave as is
          end
        end
      end

      # Expand environment variables $VAR or ${VAR}
      result = result.gsub(/\$\{([^}]+)\}|\$([A-Za-z_][A-Za-z0-9_]*)/) do
        var_name = $1 || $2
        ENV[var_name] || $&
      end

      result
    end

    # Correct directory spelling errors in a completion path
    def correct_completion_path(input)
      # Split into directory part and filename part
      if input.include?('/')
        dir_part = File.dirname(input)
        file_part = File.basename(input)
      else
        # No directory part, nothing to correct
        return nil
      end

      # Try to correct the directory part
      corrected_dir = Builtins.correct_directory_spelling(dir_part)
      return nil unless corrected_dir

      # Return corrected path with original file part
      File.join(corrected_dir, file_part)
    end
  end
end
