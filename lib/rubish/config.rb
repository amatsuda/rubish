# frozen_string_literal: true

module Rubish
  # Configuration and initialization for the shell REPL
  # Handles startup files, inputrc, aliases, job control, and signals
  module Config
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

    # Set up job control for interactive shells
    # This puts the shell in its own process group and takes control of the terminal
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
        Builtins.source([path])
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
  end
end
