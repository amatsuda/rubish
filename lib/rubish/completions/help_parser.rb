# frozen_string_literal: true

module Rubish
  module Builtins
    # ==========================================================================
    # Auto-completion by parsing --help output (fish-style)
    # ==========================================================================

    # Cache for parsed help output: { command => { subcommands: [...], options: [...], timestamp: Time } }
    @help_completion_cache = {}
    HELP_CACHE_TTL = 1800  # 30 minutes

    # Get zsh's fpath for completion file directories
    @zsh_fpath = nil
    def zsh_fpath
      return @zsh_fpath if @zsh_fpath

      @zsh_fpath = `zsh -c 'print -l $fpath' 2>/dev/null`.split("\n").select { |d| Dir.exist?(d) }
    rescue
      @zsh_fpath = []
    end

    # Timeout for help command execution (seconds)
    HELP_COMMAND_TIMEOUT = 2

    # macOS sandbox profile for running help commands safely
    # Denies network access, allows reads and writes only to safe locations
    SANDBOX_PROFILE = <<~PROFILE
      (version 1)
      (deny default)
      (allow process-fork process-exec)
      (allow file-read*)
      (allow file-read-metadata)
      (allow sysctl-read)
      (allow mach-lookup)
      (allow signal (target self))
      (deny network*)
      ; Allow writes to /dev/null and temp directories (needed by man, etc.)
      (allow file-write* (subpath "/dev"))
      (allow file-write* (subpath "/tmp"))
      (allow file-write* (subpath "/private/tmp"))
      (allow file-write* (subpath "/var/folders"))
      (allow file-write* (subpath "/private/var/folders"))
      ; Deny writes everywhere else
      (deny file-write* (subpath "/Users"))
      (deny file-write* (subpath "/System"))
      (deny file-write* (subpath "/Applications"))
    PROFILE

    # Run a help command in a sandboxed environment with timeout
    # Returns [output, success] or [nil, false] on failure/timeout
    def sandboxed_help_command(help_cmd)
      Kernel.require 'open3'
      Kernel.require 'tempfile'

      pid = nil
      output = nil
      success = false

      begin
        if RUBY_PLATFORM.include?('darwin')
          # macOS: use sandbox-exec for additional isolation
          profile_file = Tempfile.new(['sandbox', '.sb'])
          begin
            profile_file.write(SANDBOX_PROFILE)
            profile_file.close

            stdin, stdout_err, wait_thr = Open3.popen2e('sandbox-exec', '-f', profile_file.path, 'sh', '-c', help_cmd)
            pid = wait_thr.pid
            stdin.close

            # Use select with timeout to read output
            ready = IO.select([stdout_err], nil, nil, HELP_COMMAND_TIMEOUT)
            if ready
              output = stdout_err.read
              wait_thr.join(HELP_COMMAND_TIMEOUT)
              success = wait_thr.value&.success? || false
            else
              # Timeout - kill the process
              Process.kill('TERM', pid) rescue nil
              Process.kill('KILL', pid) rescue nil
              success = false
            end
            stdout_err.close
          ensure
            profile_file.unlink
          end
        else
          # Other platforms: run with timeout protection
          stdin, stdout_err, wait_thr = Open3.popen2e(help_cmd)
          pid = wait_thr.pid
          stdin.close

          ready = IO.select([stdout_err], nil, nil, HELP_COMMAND_TIMEOUT)
          if ready
            output = stdout_err.read
            wait_thr.join(HELP_COMMAND_TIMEOUT)
            success = wait_thr.value&.success? || false
          else
            Process.kill('TERM', pid) rescue nil
            Process.kill('KILL', pid) rescue nil
            success = false
          end
          stdout_err.close
        end

        [output, success]
      rescue Errno::ENOENT
        # Command not found
        [nil, false]
      rescue => e
        # Kill process if still running
        if pid
          Process.kill('TERM', pid) rescue nil
          Process.kill('KILL', pid) rescue nil
        end
        [nil, false]
      end
    end

    # Known help sources for popular commands (command => help invocation)
    # Note: git, ssh, make, man, kill have dedicated completion functions
    HELP_COMMAND_SOURCES = {
      'aws' => 'aws help',
      'bundle' => 'bundle --help',
      'gem' => 'gem help commands',
      'rails' => 'rails --help',
      'brew' => 'brew commands',
      'npm' => 'npm help',
      'yarn' => 'yarn --help',
      'cargo' => 'cargo --list',
      'docker' => 'docker --help',
      'go' => 'go help',
      'pip' => 'pip --help',
      'rustup' => 'rustup --help'
    }.freeze

    def _auto_completion(cmd, cur, prev)
      words = @comp_words
      cword = @comp_cword
      command = words[0]

      # Parse help output for this command
      parsed = parse_help_for_command(command)
      return if parsed.nil?

      # Find if we're completing a subcommand's arguments
      subcommand = nil
      words.each_with_index do |word, idx|
        next if idx == 0
        next if word.start_with?('-')
        if parsed[:subcommands].include?(word)
          subcommand = word
          break
        end
      end

      if subcommand && cword > 1
        # Try to get help for the subcommand
        sub_parsed = parse_help_for_command(command, subcommand)
        if sub_parsed
          if cur.start_with?('-')
            @compreply = sub_parsed[:options].select { |o| o.start_with?(cur) }
          else
            @compreply = sub_parsed[:subcommands].select { |s| s.start_with?(cur) }
          end
          return
        end
      end

      # Complete top-level
      if cur.start_with?('-')
        @compreply = parsed[:options].select { |o| o.start_with?(cur) }
      else
        @compreply = parsed[:subcommands].select { |s| s.start_with?(cur) }
      end
    end

    def parse_help_for_command(command, subcommand = nil)
      # Skip commands that look like shell operators or Ruby syntax
      return nil if command =~ /\A[-+:=<>|&!]\z/

      cache_key = subcommand ? "#{command} #{subcommand}" : command

      # Check cache
      cached = @help_completion_cache[cache_key]
      if cached && (Time.now - cached[:timestamp]) < HELP_CACHE_TTL
        return cached
      end

      parsed = nil

      # Try zsh completion file first (for top-level commands only)
      if subcommand.nil?
        parsed = parse_zsh_completion_file(command)
        if parsed && parsed[:subcommands].length >= 3
          parsed[:timestamp] = Time.now
          @help_completion_cache[cache_key] = parsed
          return parsed
        end
        # Reset parsed if zsh result has too few subcommands (likely false positives)
        parsed = nil
      end

      # Fall back to help output parsing
      # Note: We only try "command help" for known commands that support it,
      # because for unknown commands like "touch", "touch help" would create a file!
      help_commands = if subcommand
        ["#{command} #{subcommand} --help", "#{command} help #{subcommand}"]
      elsif HELP_COMMAND_SOURCES.key?(command)
        # Use known source for popular commands
        [HELP_COMMAND_SOURCES[command]]
      else
        # For unknown commands, only try --help and -h (not bare "help" subcommand)
        # to avoid side effects like "touch help" creating a file named "help"
        ["#{command} --help", "#{command} -h"]
      end

      help_output = nil
      help_commands.each do |help_cmd|
        # Run help command in sandbox with timeout for safety
        output, success = sandboxed_help_command(help_cmd)
        next unless success && output && output.length > 50

        help_output = output
        # Check if this output has good subcommand info
        help_parsed = parse_help_output(output)
        if help_parsed[:subcommands].length >= 3
          parsed = help_parsed
          break
        elsif parsed.nil? || help_parsed[:subcommands].length > (parsed[:subcommands]&.length || 0)
          parsed = help_parsed
        end
      end

      return nil unless parsed

      parsed[:timestamp] = Time.now
      @help_completion_cache[cache_key] = parsed
      parsed
    end

    def parse_help_output(text)
      subcommands = []
      options = []

      # Remove man page formatting:
      # - Bold: A\bA (doubled characters like "bbuunnddllee")
      # - Overstrike: +\bo (bullet points, underscore emphasis)
      text = text.gsub(/(.)\x08\1/, '\1')  # Bold: keep second char
      text = text.gsub(/.\x08/, '')         # Overstrike: keep second char (removes first)
      # Remove ANSI escape codes
      text = text.gsub(/\e\[[0-9;]*m/, '')

      lines = text.lines.map(&:chomp)
      in_commands_section = false
      in_options_section = false

      lines.each do |line|
        # Detect section headers
        if line =~ /^(Commands|COMMANDS|Subcommands|SUBCOMMANDS|Available commands):/i ||
           line =~ /commands are:$/i ||
           line =~ /^=+>\s*(Built-in\s+)?commands$/i ||
           line =~ /^(PRIMARY|UTILITIES|BUNDLE)\s+COMMANDS$/i ||
           line =~ /^AVAILABLE SERVICES$/  # AWS CLI style
          in_commands_section = true
          in_options_section = false
          next
        elsif line =~ /^(Options|OPTIONS|Flags|FLAGS|Global options):/i ||
              line =~ /^GLOBAL OPTIONS$/  # AWS CLI style
          in_commands_section = false
          in_options_section = true
          next
        elsif line =~ /^[A-Z][-A-Za-z_]+:$/ || line =~ /^[A-Z][-A-Za-z_]+\s+[-A-Za-z_]+:$/
          # Short section header (1-2 words) that's not a commands section
          # Set in_options_section to true to suppress subcommand detection
          # (sections like "Features:", "Warning categories:", "Dump List:", "YJIT options:")
          in_commands_section = false
          in_options_section = true
        end

        # Parse subcommands in different formats:
        # 1. Simple list: one command per line (brew commands)
        # 2. Table format: "  command   description" (gem help commands)
        # 3. Man page format: "bundle install(1)"
        if in_commands_section
          # Simple single-word per line (brew commands style)
          if line =~ /^([a-z][-a-z0-9_]*)$/
            subcommands << $1
          # Table format with description
          elsif line =~ /^\s{2,}([a-z][-a-z0-9_:]*)\s{2,}/
            cmd = $1
            subcommands << cmd if cmd.length < 30 && !cmd.include?('=')
          # Man page format: "bundle install(1)"
          elsif line =~ /^\s+\w+\s+([a-z][-a-z0-9_]*)\s*\(\d\)/
            subcommands << $1
          # Bullet-point format: "       o service" (AWS CLI style, from man page)
          elsif line =~ /^\s+o\s+([a-z][-a-z0-9_]+)$/
            subcommands << $1
          end
        elsif !in_options_section
          # Outside of explicit sections, try to detect command patterns
          # Table format with description (e.g., git's "   clone      Clone a repository")
          if line =~ /^\s{2,4}([a-z][-a-z0-9_]*)\s{2,}\S/
            cmd = $1
            # Skip common English words that appear in help text (e.g., "or  java [options]...")
            next if %w[or and the for to in of on at by as is it if an are be do no so].include?(cmd)
            subcommands << cmd if cmd.length < 25 && !cmd.include?('=')
          end
        end

        # Parse options - look for -x or --xxx patterns
        if line =~ /(^|\s)(--?[a-zA-Z][-a-zA-Z0-9_]*)/
          line.scan(/(?:^|\s)(--?[a-zA-Z][-a-zA-Z0-9_]*)(?:[,=\s\[]|$)/).flatten.each do |opt|
            options << opt unless opt =~ /^-\d/  # Skip things like -1, -2
          end
        end
      end

      {subcommands: subcommands.uniq, options: options.uniq}
    end

    # ==========================================================================
    # Zsh completion file parsing
    # ==========================================================================

    # Find zsh completion file for a command
    def find_zsh_completion_file(command)
      zsh_fpath.each do |dir|
        path = File.join(dir, "_#{command}")
        return path if File.exist?(path)
      end
      nil
    end

    # Parse zsh completion file to extract subcommands and options
    # First tries to find and execute the actual commands zsh uses,
    # then falls back to static parsing
    def parse_zsh_completion_file(command)
      path = find_zsh_completion_file(command)
      return nil unless path

      content = File.read(path)
      subcommands = []
      options = []

      # Strategy 1: Find and execute the commands that zsh completions use
      # Look for patterns like: $(_call_program commands cargo --list)
      # or: $(cargo --list) or `cargo --list`
      extracted_cmds = extract_zsh_completion_commands(content, command)
      extracted_cmds.each do |cmd|
        output = with_timeout(cmd, 2)
        next unless output && output.length > 10

        # Parse the output for subcommands
        output.each_line do |line|
          line = line.strip
          # Common formats:
          # "    subcommand   description" (cargo --list)
          # "subcommand" (simple list)
          # "subcommand:description" (already parsed)
          if line =~ /^\s{2,}(\S+)/ || line =~ /^([a-z][-a-z0-9_]+)(?:\s|$|:)/
            sub = $1
            subcommands << sub if sub.length < 30 && sub =~ /^[a-z]/
          end
        end
      end

      # Strategy 2: Parse inline subcommand definitions
      # e.g., 'add:Add a dependency'
      content.scan(/'([a-z][-a-z0-9_]*):[^']*'/).each do |match|
        subcommands << match[0]
      end

      # Strategy 3: Parse array definitions
      # commands=( 'add:desc' 'build:desc' ... ) or hardcoded arrays
      content.scan(/(?:commands?|cmds|subcmds)\s*=\s*\(\s*([^)]+)\)/m).each do |match|
        # Match 'subcommand:description' or 'subcommand' patterns
        match[0].scan(/'([a-z][-a-z0-9_]+)(?::|')/).each do |cmd|
          subcommands << cmd[0] if cmd[0].length < 25
        end
      end

      # Strategy 4: Options from _arguments specs
      content.scan(/'(-[a-zA-Z])['\[\s]/).each do |match|
        options << match[0]
      end
      content.scan(/'(--[a-zA-Z][-a-zA-Z0-9_]*)['\[\s=]/).each do |match|
        options << match[0]
      end

      return nil if subcommands.empty? && options.empty?

      {
        subcommands: subcommands.uniq.sort,
        options: options.uniq.sort,
        source: :zsh
      }
    rescue
      nil
    end

    # Extract shell commands from zsh completion file that fetch subcommands
    def extract_zsh_completion_commands(content, command)
      cmds = []

      # Pattern: _call_program <tag> <command>
      # e.g., _call_program commands cargo --list
      content.scan(/_call_program\s+(\w+)\s+([^)"'\n]+)/).each do |match|
        tag, cmd = match[0], match[1].strip
        # Only include commands that look like subcommand listing
        next unless cmd.start_with?(command)
        # Tag must indicate commands/subcommands
        next unless tag =~ /^commands?$/i
        cmds << cmd
      end

      # Pattern: $(<command>) command substitution for listing
      # e.g., $(cargo --list) - must be simple "command --list" style
      content.scan(/\$\(([^)]+)\)/).each do |match|
        cmd = match[0].strip
        next unless cmd.start_with?(command)
        next if cmd.include?('_call_program')
        # Only simple list commands: "cmd --list" or "cmd help"
        next unless cmd =~ /^#{Regexp.escape(command)}\s+(--list|help|commands)$/
        cmds << cmd
      end

      # Pattern: `<command>` backtick substitution
      content.scan(/`([^`]+)`/).each do |match|
        cmd = match[0].strip
        next unless cmd.start_with?(command)
        next unless cmd =~ /^#{Regexp.escape(command)}\s+(--list|help|commands)$/
        cmds << cmd
      end

      cmds.uniq
    end

    # Execute a command with timeout, returns output or nil
    def with_timeout(cmd, timeout = 2)
      output = nil
      begin
        Timeout.timeout(timeout) do
          output = `#{cmd} 2>/dev/null`
        end
      rescue Timeout::Error
        output = nil
      end
      output
    end
  end
end
