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

    # Timeout for help command execution (seconds). Defaults to a value
    # generous enough for frameworks that boot before printing `--help`
    # (rails inside an app dir typically needs 3–5s). Tunable via env
    # for users on slow machines or in unusual sandboxes.
    HELP_COMMAND_TIMEOUT_DEFAULT = 5
    def self.help_command_timeout
      t = ENV['RUBISH_HELP_TIMEOUT'].to_i
      t > 0 ? t : HELP_COMMAND_TIMEOUT_DEFAULT
    end
    HELP_COMMAND_TIMEOUT = HELP_COMMAND_TIMEOUT_DEFAULT  # kept for back-compat

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

      timeout = Builtins.help_command_timeout
      $stderr.puts "[rubish-comp] running: #{help_cmd} (timeout=#{timeout}s)" if ENV['RUBISH_DEBUG_COMPLETION']

      pid = nil
      output = nil
      success = false
      started_at = Time.now

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
            ready = IO.select([stdout_err], nil, nil, timeout)
            if ready
              output = stdout_err.read
              wait_thr.join(timeout)
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

          ready = IO.select([stdout_err], nil, nil, timeout)
          if ready
            output = stdout_err.read
            wait_thr.join(timeout)
            success = wait_thr.value&.success? || false
          else
            Process.kill('TERM', pid) rescue nil
            Process.kill('KILL', pid) rescue nil
            success = false
          end
          stdout_err.close
        end

        if ENV['RUBISH_DEBUG_COMPLETION']
          elapsed = (Time.now - started_at).round(2)
          $stderr.puts "[rubish-comp]   -> success=#{success} elapsed=#{elapsed}s output=#{output&.length || 0} bytes"
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

    # Known help sources for popular commands (command => help invocation).
    # Required for any command whose subcommand listing lives behind a
    # non-default invocation; the auto-fallback only tries `--help`/`-h`,
    # never `cmd help` (which would risk side effects like `touch help`
    # creating a file). Note: git, ssh, make, man, kill have dedicated
    # completion functions elsewhere.
    HELP_COMMAND_SOURCES = {
      # Required — default `--help` is missing, wrong, or much worse
      'aws'       => 'aws help',
      'brew'      => 'brew commands',
      'cargo'     => 'cargo --list',
      'composer'  => 'composer list',
      'gem'       => 'gem help commands',
      'go'        => 'go help',
      'hg'        => 'hg help',
      'launchctl' => 'launchctl help',     # launchctl rejects --help
      'npm'       => 'npm help',
      'pyenv'     => 'pyenv commands',
      'rbenv'     => 'rbenv commands',

      # `--help` works; entry pins the preferred invocation
      'bun'       => 'bun --help',
      'bundle'    => 'bundle --help',
      'deno'      => 'deno --help',
      'docker'    => 'docker --help',
      'gcloud'    => 'gcloud --help',
      'gh'        => 'gh --help',
      'glab'      => 'glab --help',
      'helm'      => 'helm --help',
      'jj'        => 'jj --help',
      'kubectl'   => 'kubectl --help',
      'mise'      => 'mise --help',
      'pip'       => 'pip --help',
      'pnpm'      => 'pnpm --help',
      'podman'    => 'podman --help',
      'poetry'    => 'poetry --help',
      'rails'     => 'rails --help',
      'rustup'    => 'rustup --help',
      'terraform' => 'terraform --help',
      'uv'        => 'uv --help',
      'yarn'      => 'yarn --help',
    }.freeze

    # Depth cap for greedy chain descent in `_auto_completion`. Each
    # extra level costs a sandbox help-command spawn on a cold cache
    # (≤ HELP_COMMAND_TIMEOUT seconds). After the first invocation
    # subsequent lookups in the same chain are served from cache for
    # HELP_CACHE_TTL.
    HELP_CHAIN_DEPTH_CAP = 5

    def _auto_completion(cmd, cur, prev)
      words = @comp_words
      cword = @comp_cword
      command = words[0]

      parsed = parse_help_for_command(command)
      return if parsed.nil?

      # Greedy descent through nested subcommands: keep parsing
      # `cmd a b c --help` for as long as each next word is a known
      # subcommand at the current level. Flags between subcommands
      # (e.g. `rails -v g -d scaffold`) are skipped. Stops on unknown
      # words, on `cword` (the position being completed), at the depth
      # cap, or when help parsing returns nothing for a deeper chain.
      chain = []
      idx = 1
      while idx < cword && chain.length < HELP_CHAIN_DEPTH_CAP
        word = words[idx]
        if word && !word.empty? && !word.start_with?('-') &&
           parsed[:subcommands].include?(word)
          chain << word
          next_parsed = parse_help_for_command(command, *chain)
          break if next_parsed.nil?
          parsed = next_parsed
        end
        idx += 1
      end

      if cur.start_with?('-')
        @compreply = parsed[:options].select { |o| o.start_with?(cur) }
      else
        @compreply = parsed[:subcommands].select { |s| s.start_with?(cur) }
      end
    end

    def parse_help_for_command(command, *subcommand_chain)
      # Skip commands that look like shell operators or Ruby syntax
      return nil if command.nil? || command =~ /\A[-+:=<>|&!]\z/

      cache_key = ([command] + subcommand_chain).join(' ')

      # Check cache
      cached = @help_completion_cache[cache_key]
      if cached && (Time.now - cached[:timestamp]) < HELP_CACHE_TTL
        return cached
      end

      parsed = nil

      # Try zsh completion file first (for top-level commands only)
      if subcommand_chain.empty?
        parsed = parse_zsh_completion_file(command)
        if parsed && parsed[:subcommands].length >= 3
          parsed[:timestamp] = Time.now
          @help_completion_cache[cache_key] = parsed
          return parsed
        end
        # Reset parsed if zsh result has too few subcommands (likely false positives)
        parsed = nil
      end

      # Fall back to help output parsing.
      # For nested calls (`rails g scaffold`) we always try
      # `cmd a b c --help` and `cmd help a b c`. For top-level we use
      # the curated invocation or fall back to --help/-h.
      # Note: bare "command help" is only tried for known commands, so
      # we don't accidentally invoke things like `touch help` (would
      # create a file). Nested calls are always safe because the full
      # chain disambiguates intent.
      help_commands = if subcommand_chain.any?
        rest = subcommand_chain.join(' ')
        # For nested calls only try `cmd a b ... --help`. The `cmd help
        # a b ...` form is unreliable here: many CLIs (rails for one)
        # treat `help` followed by anything they don't recognize as a
        # silent no-op and print their top-level help instead. That
        # output would parse as a perfectly valid (but wrong) result —
        # `rails help generate` returns rails's top-level commands, so
        # completion for `rails generate <TAB>` would offer rails's
        # top-level subcommands instead of the generator names.
        ["#{command} #{rest} --help"]
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
        next unless output && output.length > 50
        # Accept non-zero exits when the captured output contains a usage: definition.
        # macOS/BSD tools reject --help with non-zero status but still print usage.
        next unless success || output =~ /\busage:/i

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

      lines.each_with_index do |line, line_idx|
        # Detect section headers
        if line =~ /^(All\s+)?(Commands|COMMANDS|Subcommands|SUBCOMMANDS|Available commands):/i ||
           line =~ /commands are:$/i ||
           line =~ /^=+>\s*(Built-in\s+)?commands$/i ||
           line =~ /^[A-Z][A-Z ]*COMMANDS?$/ ||  # PRIMARY/CORE/ADDITIONAL/etc. COMMANDS (gh, bundle, etc.)
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
          # Short section header (1-2 words). Could be a non-commands
          # section ("Features:", "Warning categories:", "Dump List:"
          # — content shouldn't be treated as subcommands) or a
          # command-listing group ("Rails:" / "ActionMailbox:" etc.
          # in `rails generate --help`, listing generator names). Peek
          # at the next non-blank line to disambiguate.
          # Exception: "Usage:" / "Synopsis:" / "Description:" are
          # preamble headers — don't flip any flags, let outside-section
          # detection handle whatever follows.
          unless line =~ /\A(Usage|Synopsis|Description):\z/i
            peek = nil
            (line_idx + 1).upto([line_idx + 4, lines.length - 1].min) do |j|
              candidate = lines[j]
              if candidate && !candidate.strip.empty?
                peek = candidate
                break
              end
            end
            if peek && peek =~ /^\s+(-|\[-)/
              # Next line looks like an option (`  -x ...` or `  [--foo]`)
              in_commands_section = false
              in_options_section = true
            elsif peek && peek =~ /^\s+[a-z][-a-z0-9_:]*(\s*$|\s{2,}\S)/
              # Next line looks like a subcommand (bare identifier or
              # `  name  description` table format)
              in_commands_section = true
              in_options_section = false
            else
              # Can't tell — fall back to the conservative behavior of
              # suppressing subcommand detection (matches the previous
              # default for these headers).
              in_commands_section = false
              in_options_section = true
            end
          end
        end

        # Parse subcommands in different formats:
        # 1. Simple list: one command per line (brew commands)
        # 2. Table format: "  command   description" (gem help commands)
        # 3. Man page format: "bundle install(1)"
        # 4. Tab-indented table (launchctl): "\tname  description"
        # 5. Comma-separated paragraph under "All commands:" (npm)
        if in_commands_section
          # Simple single-word per line (brew commands style)
          if line =~ /^([a-z][-a-z0-9_]*)$/
            subcommands << $1
          # Table format with description (trailing ':' on the name is gh-style)
          elsif line =~ /^\s{2,}([a-z][-a-z0-9_]*):?\s{2,}/
            cmd = $1
            subcommands << cmd if cmd.length < 30 && !cmd.include?('=')
          # Indented bare identifier (rails generate's "Rails:" / "ActionText:"
          # generator groups list each name on its own indented line, with
          # no description). Colons are allowed in the middle (Thor
          # namespacing: `action_mailbox:install`).
          elsif line =~ /^\s+([a-z][-a-z0-9_:]*)\s*$/
            cmd = $1
            subcommands << cmd if cmd.length < 40 && !cmd.include?('=')
          # Tab-indented table (launchctl style: "\tname  description")
          elsif line =~ /^\t+([a-z][-a-z0-9_]*):?\s{2,}/
            cmd = $1
            subcommands << cmd if cmd.length < 30 && !cmd.include?('=')
          # Man page format: "bundle install(1)"
          elsif line =~ /^\s+\w+\s+([a-z][-a-z0-9_]*)\s*\(\d\)/
            subcommands << $1
          # Bullet-point format: "       o service" (AWS CLI style, from man page)
          elsif line =~ /^\s+o\s+([a-z][-a-z0-9_]+)$/
            subcommands << $1
          # Comma-separated paragraph (npm "All commands:" style)
          elsif line =~ /^\s+[a-z][-a-z0-9_]+,/
            line.split(',').each do |part|
              part = part.strip
              subcommands << part if part =~ /\A[a-z][-a-z0-9_]+\z/ && part.length < 25
            end
          end
        elsif !in_options_section
          # Outside of explicit sections, try to detect command patterns
          # Table format with description (e.g., git's "   clone      Clone a repository")
          # Indent widened to 2..8 spaces so pnpm-style 6-space lists are picked up.
          if line =~ /^\s{2,8}([a-z][-a-z0-9_]*):?\s{2,}\S/
            cmd = $1
            # Skip common English words that appear in help text (e.g., "or  java [options]...")
            next if %w[or and the for to in of on at by as is it if an are be do no so].include?(cmd)
            subcommands << cmd if cmd.length < 25 && !cmd.include?('=')
          # Tab-indented table without a section header (launchctl)
          elsif line =~ /^\t+([a-z][-a-z0-9_]*):?\s{2,}\S/
            cmd = $1
            next if %w[or and the for to in of on at by as is it if an are be do no so].include?(cmd)
            subcommands << cmd if cmd.length < 25 && !cmd.include?('=')
          end
        end

        # Parse options - look for -x or --xxx patterns.
        # Accept `[` as a leading char too: rails generate / Thor wraps each
        # option in brackets like `[--skip-namespace]`; same for `]` as the
        # trailing terminator.
        if line =~ /(^|[\s\[])(--?[a-zA-Z][-a-zA-Z0-9_]*)/
          line.scan(/(?:^|[\s\[])(--?[a-zA-Z][-a-zA-Z0-9_]*)(?:[,=\s\[\]]|$)/).flatten.each do |opt|
            options << opt unless opt =~ /^-\d/  # Skip things like -1, -2
          end
        end
        # Bundled short flags from BSD-style usage: [-abc] -> -a, -b, -c.
        # Allow `@%,` inside the bundle (BSD ls uses these) but only emit
        # alphanumeric chars as individual flags.
        line.scan(/\[-([A-Za-z0-9@%,]{2,})\]/).flatten.each do |bundle|
          bundle.each_char { |c| options << "-#{c}" if c =~ /[A-Za-z0-9]/ }
        end
      end

      # Drop bundles that slipped past the bracket parser. Real short
      # flags are 1-2 chars after a single dash; anything longer is
      # almost certainly a bundle (e.g. BSD usage `[-aclpSsvXx]`).
      options.reject! { |o| o =~ /\A-[A-Za-z]{3,}\z/ }

      # Fallback: if structured parsing found nothing, treat the output as a
      # bare command list (pyenv commands / rbenv commands style — no section
      # headers, just one identifier per line). Conservative: only short
      # lowercase identifiers, with an English-word skip list to filter
      # accidental matches from prose lines like a bare "usage" or "version".
      if subcommands.empty?
        # Conservative English/prose skip list. Deliberately does NOT include
        # words like "commands", "install", "version" — they're legitimate
        # subcommand names for tools like pyenv / rbenv whose bare-list
        # output we're trying to parse here.
        bare_skip = %w[
          or and the for to in of on at by as is it if an are be do no so
          usage description options option example examples
          name names note notes copyright author authors arguments synopsis
        ].freeze
        lines.each do |bare|
          next unless bare =~ /\A([a-z][-a-z0-9_]+)\z/
          cmd = $1
          next if bare_skip.include?(cmd) || cmd.length > 25
          subcommands << cmd
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
