# frozen_string_literal: true

module Rubish
  # Terminal control functions for job control
  module Terminal
    extend Fiddle::Importer
    dlload Fiddle::Handle::DEFAULT

    extern 'int tcsetpgrp(int, int)'
    extern 'int tcgetpgrp(int)'

    STDIN_FD = 0

    # Give terminal control to a process group
    def self.set_foreground(pgid)
      tcsetpgrp(STDIN_FD, pgid)
    rescue
      # Ignore errors (e.g., not a tty)
    end

    # Get current foreground process group
    def self.get_foreground
      tcgetpgrp(STDIN_FD)
    rescue
      nil
    end

    # Check if stdin is a tty
    def self.tty?
      $stdin.tty?
    rescue
      false
    end
  end

  # Simple exit status for builtins
  ExitStatus = Struct.new(:exitstatus) do
    def success?
      exitstatus == 0
    end
  end

  # Status for noclobber failures
  class NoclobberStatus
    def exitstatus
      1
    end

    def success?
      false
    end
  end

  # Status for restricted mode failures
  class RestrictedStatus
    def exitstatus
      1
    end

    def success?
      false
    end
  end

  class Command
    attr_reader :name, :pid, :status
    attr_accessor :stdin, :stdout, :stderr, :block, :prefix_env

    # Class-level accessors for function support in pipelines
    @function_checker = nil
    @function_caller = nil

    class << self
      attr_accessor :function_checker, :function_caller
    end

    def self.function?(name)
      @function_checker&.call(name) || false
    end

    def self.call_function(name, args)
      @function_caller&.call(name, args)
    end

    # Execute a command with proper error handling for command not found / permission denied
    def self.safe_exec(cmd_name, cmd_path, *args)
      exec(cmd_path, *args)
    rescue Errno::ENOENT
      $stderr.puts "rubish: #{cmd_name}: command not found"
      exit(127)
    rescue Errno::EACCES
      $stderr.puts "rubish: #{cmd_path}: Permission denied"
      exit(126)
    end

    def initialize(name, *args, skip_functions: false, &block)
      @name = name
      @args = expand_args(args)
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @block = block
      @ran = false
      @skip_functions = skip_functions
    end

    def args
      @args
    end

    def ran?
      @ran
    end

    def success?
      @status&.success? || false
    end

    def run
      return self if @ran
      @ran = true

      # If noclobber prevented redirection, fail without running
      if @noclobber_failed
        @status = NoclobberStatus.new
        return self
      end

      # If restricted mode prevented redirection, fail without running
      if @restricted_failed
        @status = RestrictedStatus.new
        return self
      end

      if @block
        run_with_block
      else
        run_simple
      end
    end

    def |(other)
      Pipeline.new(self, other)
    end

    def redirect_out(file)
      # Restricted mode: cannot redirect output
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      # Check noclobber: if set and file exists, fail
      if Builtins.set_option?('C') && File.exist?(file)
        $stderr.puts "rubish: #{file}: cannot overwrite existing file"
        @noclobber_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      self
    end

    def redirect_clobber(file)
      # Restricted mode: cannot redirect output
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      # Force overwrite even with noclobber (>|)
      @stdout = File.open(file, 'w')
      self
    end

    def redirect_append(file)
      # Restricted mode: cannot redirect output
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stdout = File.open(file, 'a')
      self
    end

    def redirect_in(file)
      @stdin = File.open(file, 'r')
      self
    end

    def redirect_err(file)
      # Restricted mode: cannot redirect output
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stderr = File.open(file, 'w')
      self
    end

    def redirect_err_to_out
      # Used for |& - redirect stderr to stdout before piping
      @stderr = :stdout
      self
    end

    def dup_out(target)
      # >&N - duplicate stdout to file descriptor N
      # >&- - close stdout
      # >&file - redirect stdout to file (same as >file)
      case target
      when '1'
        # >&1 - no-op, stdout already goes to stdout
        self
      when '2'
        # >&2 - redirect stdout to stderr
        @stdout = :stderr
        self
      when '-'
        # >&- - close stdout
        @stdout = :closed
        self
      else
        # >&file - redirect to file
        redirect_out(target)
      end
    end

    def dup_in(target)
      # <&N - duplicate stdin from file descriptor N
      # <&- - close stdin
      case target
      when '0'
        # <&0 - no-op
        self
      when '-'
        # <&- - close stdin
        @stdin = :closed
        self
      else
        # <&N - not commonly used, treat as redirect
        redirect_in(target)
      end
    end

    private

    def expand_args(args)
      # Globs are expanded at codegen level, here we just handle types
      args.flat_map do |arg|
        case arg
        when Array
          arg.map(&:to_s)
        when Regexp
          arg.source
        else
          arg.to_s
        end
      end
    end

    def run_simple
      # Restricted mode: cannot run commands containing '/'
      if Builtins.restricted_mode? && name.include?('/')
        $stderr.puts "rubish: #{name}: restricted: cannot specify `/' in command names"
        @status = RestrictedStatus.new
        return self
      end

      # Resolve command path before forking (so hash updates are visible in parent)
      cmd_path = resolve_command_path(name)

      # Extract keyword assignments if -k is set
      cmd_args, keyword_env = extract_keyword_assignments(@args)

      # Check if job control (monitor mode) is enabled
      job_control = Builtins.set_option?('m')

      @pid = fork do
        # Set up job control in child if enabled
        if job_control
          # Create new process group with this process as leader
          Process.setpgid(0, 0)
          # Reset signal handlers so Ctrl-Z works
          trap('TSTP', 'DEFAULT')
          trap('TTIN', 'DEFAULT')
          trap('TTOU', 'DEFAULT')
        end

        # Handle stdin redirection
        if @stdin == :closed
          $stdin.close
        elsif @stdin
          $stdin.reopen(@stdin)
        end

        # Handle stdout redirection
        if @stdout == :stderr
          # >&2 - redirect stdout to stderr
          $stdout.reopen($stderr)
        elsif @stdout == :closed
          $stdout.close
        elsif @stdout
          $stdout.reopen(@stdout)
        end

        # Handle stderr redirection
        if @stderr == :stdout
          # |& or 2>&1 - redirect stderr to stdout
          $stderr.reopen($stdout)
        elsif @stderr == :closed
          $stderr.close
        elsif @stderr
          $stderr.reopen(@stderr)
        end

        # Set keyword environment variables
        keyword_env.each { |k, v| ENV[k] = v }

        # Set prefix environment variables (e.g., FOO=bar cmd)
        @prefix_env&.each { |k, v| ENV[k] = v }

        # Check if this is a user-defined function (unless skip_functions is set)
        if !@skip_functions && Command.function?(name)
          result = Command.call_function(name, cmd_args)
          exit(result ? 0 : 1)
        elsif cmd_path.include?('/') && File.directory?(cmd_path)
          # Only check for directory if path was explicitly given or resolved
          # Don't check bare command names against current directory
          $stderr.puts "rubish: #{cmd_path}: Is a directory"
          exit(126)
        else
          Command.safe_exec(name, cmd_path, *cmd_args)
        end
      end

      @stdin&.close unless @stdin == $stdin || @stdin.is_a?(Symbol)
      @stdout&.close unless @stdout == $stdout || @stdout.is_a?(Symbol)

      if job_control
        # Set process group in parent too (race condition protection)
        Process.setpgid(@pid, @pid) rescue nil

        shell_pgid = Process.getpgrp

        # Use 'IGNORE' for SIGTTOU/SIGTTIN (maps to SIG_IGN) so tcsetpgrp works from background
        # Use a noop proc for SIGCHLD because 'IGNORE' causes OS to auto-reap children
        noop = proc {}
        old_chld = trap('CHLD', noop)
        old_ttou = trap('TTOU', 'IGNORE')
        old_ttin = trap('TTIN', 'IGNORE')

        # Give terminal control to the child process group
        # This allows the child to receive Ctrl-Z (SIGTSTP)
        Terminal.set_foreground(@pid) if Terminal.tty?

        begin
          # Wait with WUNTRACED to detect stopped processes (Ctrl-Z)
          _, @status = Process.wait2(@pid, Process::WUNTRACED)
        ensure
          # Take back terminal control BEFORE restoring signal handlers
          Terminal.set_foreground(shell_pgid) if Terminal.tty?

          # Restore signal handlers after we have terminal control back
          trap('CHLD', old_chld || 'DEFAULT')
          trap('TTOU', old_ttou || 'DEFAULT')
          trap('TTIN', old_ttin || 'DEFAULT')
        end

        # If the process was stopped, add it to the job manager
        if @status&.stopped?
          command_str = ([name] + @args).join(' ')
          job = JobManager.instance.add(
            pid: @pid,
            pgid: @pid,
            command: command_str
          )
          job.status = :stopped
          $stderr.puts "\n[#{job.id}]+  Stopped                 #{command_str}"
        end
      else
        Process.wait(@pid)
        @status = $?
      end
      self
    end

    def run_with_block
      reader, writer = IO.pipe

      # Resolve command path before forking (so hash updates are visible in parent)
      cmd_path = resolve_command_path(name)

      # Extract keyword assignments if -k is set
      cmd_args, keyword_env = extract_keyword_assignments(@args)

      @pid = fork do
        reader.close
        $stdin.reopen(@stdin) if @stdin
        $stdout.reopen(writer)
        if @stderr == :stdout
          # |& - redirect stderr to stdout (which is now writer)
          $stderr.reopen($stdout)
        elsif @stderr
          $stderr.reopen(@stderr)
        end

        # Set keyword environment variables
        keyword_env.each { |k, v| ENV[k] = v }

        # Set prefix environment variables (e.g., FOO=bar cmd)
        @prefix_env&.each { |k, v| ENV[k] = v }

        Command.safe_exec(name, cmd_path, *cmd_args)
      end

      writer.close
      @stdin&.close unless @stdin == $stdin || @stdin.is_a?(Symbol)

      # Yield each line to block
      reader.each_line do |line|
        @block.call(line.chomp)
      end
      reader.close

      Process.wait(@pid)
      @status = $?
      self
    end

    def resolve_command_path(cmd)
      # If absolute path or not using hashall, return as-is
      return cmd if cmd.include?('/') || !Builtins.set_option?('h')

      # Check hash first
      cached = Builtins.hash_lookup(cmd)
      if cached && !Builtins.execignore?(cached)
        # checkhash: verify the cached path is still valid
        if Builtins.shopt_enabled?('checkhash')
          unless File.executable?(cached) && !File.directory?(cached)
            # Cached path is no longer valid, remove from hash and re-search
            Builtins.hash_delete(cmd)
            cached = nil
          end
        end
        return cached if cached
      end

      # Search PATH and cache if found
      path_dirs = (ENV['PATH'] || '').split(File::PATH_SEPARATOR)
      path_dirs.each do |dir|
        full_path = File.join(dir, cmd)
        next if Builtins.execignore?(full_path)
        if File.executable?(full_path) && !File.directory?(full_path)
          Builtins.hash_store(cmd, full_path)
          return full_path
        end
      end

      # Not found in PATH, return original (exec will fail with proper error)
      cmd
    end

    def extract_keyword_assignments(args)
      # When -k (keyword) is set, extract VAR=value from all args
      return [args, {}] unless Builtins.set_option?('k')

      keyword_env = {}
      remaining_args = []

      args.each do |arg|
        if arg.is_a?(String) && arg.match?(/\A[A-Za-z_][A-Za-z0-9_]*=/)
          # This is a keyword assignment
          name, value = arg.split('=', 2)
          keyword_env[name] = value || ''
        else
          remaining_args << arg
        end
      end

      [remaining_args, keyword_env]
    end
  end

  class Pipeline
    attr_reader :commands, :status, :statuses
    attr_accessor :block

    def initialize(*commands)
      @commands = commands.flatten
      @ran = false
      @block = nil
    end

    def |(other)
      @commands << other
      self
    end

    def ran?
      @ran
    end

    def success?
      @status&.success? || false
    end

    def run(&block)
      return self if @ran
      @ran = true

      if block || @block
        run_with_block(block || @block)
      else
        run_simple
      end
    end

    def redirect_out(file)
      @commands.last.redirect_out(file)
      self
    end

    def redirect_clobber(file)
      @commands.last.redirect_clobber(file)
      self
    end

    def redirect_append(file)
      @commands.last.redirect_append(file)
      self
    end

    def redirect_in(file)
      @commands.first.redirect_in(file)
      self
    end

    def redirect_err(file)
      @commands.last.redirect_err(file)
      self
    end

    def redirect_err_to_out
      @commands.last.redirect_err_to_out
      self
    end

    def dup_out(target)
      @commands.last.dup_out(target)
      self
    end

    def dup_in(target)
      @commands.last.dup_in(target)
      self
    end

    private

    def run_simple
      # Check if lastpipe is enabled - run last command in current shell
      use_lastpipe = Builtins.shopt_enabled?('lastpipe') && @commands.length > 1

      # Check if job control (monitor mode) is enabled
      job_control = Builtins.set_option?('m')

      # Set up pipes between commands
      pipes = (@commands.length - 1).times.map { IO.pipe }

      # Determine which commands to fork (all except last if lastpipe)
      fork_count = use_lastpipe ? @commands.length - 1 : @commands.length

      # For job control, all processes in the pipeline share a process group
      # The first process's PID becomes the PGID
      pgid = nil

      pids = @commands[0...fork_count].each_with_index.map do |cmd, i|
        # Set stdin from previous pipe (except first command)
        cmd.stdin ||= pipes[i - 1][0] if i > 0

        # Set stdout to next pipe (except last command, but we're not forking last with lastpipe)
        cmd.stdout ||= pipes[i][1] if i < @commands.length - 1

        fork do
          # Set up job control in child if enabled
          if job_control
            # First process becomes the process group leader
            # Others join that process group
            if pgid
              Process.setpgid(0, pgid)
            else
              Process.setpgid(0, 0)
            end
            # Reset signal handlers so Ctrl-Z works
            trap('TSTP', 'DEFAULT')
            trap('TTIN', 'DEFAULT')
            trap('TTOU', 'DEFAULT')
          end

          # Close unused pipe ends
          pipes.each_with_index do |(reader, writer), j|
            if j == i - 1
              writer.close  # close write end of our input pipe
            elsif j == i
              reader.close  # close read end of our output pipe
            else
              reader.close
              writer.close
            end
          end

          $stdin.reopen(cmd.stdin) if cmd.stdin
          $stdout.reopen(cmd.stdout) if cmd.stdout
          $stderr.reopen(cmd.stderr) if cmd.stderr

          # Set prefix environment variables (e.g., FOO=bar cmd)
          cmd.prefix_env&.each { |k, v| ENV[k] = v } if cmd.respond_to?(:prefix_env)

          # Handle different command types
          if cmd.is_a?(Subshell)
            # Run subshell block
            result = cmd.instance_variable_get(:@block).call
            result.run if result.is_a?(Command) || result.is_a?(Pipeline)
            exit(result.respond_to?(:success?) && result.success? ? 0 : 0)
          elsif cmd.is_a?(HeredocCommand)
            # Run heredoc command in child process
            cmd.run
            exit(cmd.success? ? 0 : 1)
          elsif Command.function?(cmd.name)
            result = Command.call_function(cmd.name, cmd.args)
            exit(result ? 0 : 1)
          else
            Command.safe_exec(cmd.name, cmd.name, *cmd.args)
          end
        end.tap do |pid|
          # Set up process group in parent (first process becomes leader)
          if job_control
            if pgid.nil?
              pgid = pid
              Process.setpgid(pid, pid) rescue nil
            else
              Process.setpgid(pid, pgid) rescue nil
            end
          end
        end
      end

      # Handle lastpipe: run last command in current shell
      last_status = nil
      if use_lastpipe
        last_cmd = @commands.last
        last_pipe_reader = pipes.last[0]

        # Close write ends of all pipes in parent
        pipes.each { |_, writer| writer.close }

        # Close read ends of pipes except the last one (which we'll use for stdin)
        pipes[0...-1].each { |reader, _| reader.close }

        # Save original stdin
        original_stdin = $stdin.dup

        begin
          # Redirect stdin to read from the pipe
          $stdin.reopen(last_pipe_reader)

          # Run the last command in current shell
          if last_cmd.is_a?(Command) && Builtins.builtin?(last_cmd.name)
            success = Builtins.run(last_cmd.name, last_cmd.args)
            last_status = ExitStatus.new(success ? 0 : 1)
          elsif last_cmd.is_a?(Command) && Command.function?(last_cmd.name)
            result = Command.call_function(last_cmd.name, last_cmd.args)
            last_status = ExitStatus.new(result ? 0 : 1)
          else
            # External command - must fork
            pid = fork do
              $stdout.reopen(last_cmd.stdout) if last_cmd.stdout
              $stderr.reopen(last_cmd.stderr) if last_cmd.stderr
              Command.safe_exec(last_cmd.name, last_cmd.name, *last_cmd.args)
            end
            Process.wait(pid)
            last_status = $?
          end
        ensure
          # Restore original stdin
          $stdin.reopen(original_stdin)
          original_stdin.close
          last_pipe_reader.close
        end
      else
        # Parent closes all pipe ends
        pipes.each do |reader, writer|
          reader.close
          writer.close
        end
      end

      shell_pgid = Process.getpgrp
      stopped = false

      if job_control && pgid
        # Use 'IGNORE' for SIGTTOU/SIGTTIN (maps to SIG_IGN) so tcsetpgrp works from background
        # Use a noop proc for SIGCHLD because 'IGNORE' causes OS to auto-reap children
        noop = proc {}
        old_chld = trap('CHLD', noop)
        old_ttou = trap('TTOU', 'IGNORE')
        old_ttin = trap('TTIN', 'IGNORE')

        # Give terminal control to the pipeline's process group
        Terminal.set_foreground(pgid) if Terminal.tty?

        begin
          # Wait for all forked children and collect statuses
          statuses = pids.map do |pid|
            _, status = Process.wait2(pid, Process::WUNTRACED)
            stopped = true if status.stopped?
            status
          end
        ensure
          # Take back terminal control BEFORE any output
          Terminal.set_foreground(shell_pgid) if Terminal.tty?

          # Restore signal handlers
          trap('CHLD', old_chld || 'DEFAULT')
          trap('TTOU', old_ttou || 'DEFAULT')
          trap('TTIN', old_ttin || 'DEFAULT')
        end
      else
        # Wait for all forked children and collect statuses
        statuses = pids.map do |pid|
          Process.wait(pid)
          $?
        end
      end

      # If any process was stopped (Ctrl-Z), add the pipeline as a stopped job
      if job_control && stopped && pgid
        command_str = @commands.map { |c| c.respond_to?(:name) ? ([c.name] + c.args).join(' ') : c.to_s }.join(' | ')
        job = JobManager.instance.add(
          pid: pgid,
          pgid: pgid,
          command: command_str
        )
        job.status = :stopped
        puts "\n[#{job.id}]+  Stopped                 #{command_str}"
      end

      # Add last command status if using lastpipe
      statuses << last_status if use_lastpipe && last_status

      @statuses = statuses
      @status = determine_pipeline_status(statuses)
      self
    end

    def run_with_block(block)
      # Set up pipes between commands, with last one going to a pipe we read
      pipes = @commands.length.times.map { IO.pipe }

      pids = @commands.each_with_index.map do |cmd, i|
        # Set stdin from previous pipe (except first command)
        cmd.stdin ||= pipes[i - 1][0] if i > 0

        # Set stdout to next pipe
        cmd.stdout ||= pipes[i][1]

        fork do
          # Close unused pipe ends
          pipes.each_with_index do |(reader, writer), j|
            if j == i - 1
              writer.close
            elsif j == i
              reader.close
            else
              reader.close
              writer.close
            end
          end

          $stdin.reopen(cmd.stdin) if cmd.stdin
          $stdout.reopen(cmd.stdout) if cmd.stdout
          $stderr.reopen(cmd.stderr) if cmd.stderr

          # Set prefix environment variables (e.g., FOO=bar cmd)
          cmd.prefix_env&.each { |k, v| ENV[k] = v } if cmd.respond_to?(:prefix_env)

          # Handle different command types
          if cmd.is_a?(Subshell)
            # Run subshell block
            result = cmd.instance_variable_get(:@block).call
            result.run if result.is_a?(Command) || result.is_a?(Pipeline)
            exit(result.respond_to?(:success?) && result.success? ? 0 : 0)
          elsif cmd.is_a?(HeredocCommand)
            # Run heredoc command in child process
            cmd.run
            exit(cmd.success? ? 0 : 1)
          elsif Command.function?(cmd.name)
            result = Command.call_function(cmd.name, cmd.args)
            exit(result ? 0 : 1)
          else
            Command.safe_exec(cmd.name, cmd.name, *cmd.args)
          end
        end
      end

      # Parent closes write ends
      pipes.each { |_, writer| writer.close }

      # Close intermediate read ends
      pipes[0...-1].each { |reader, _| reader.close }

      # Read from last pipe and yield to block
      last_reader = pipes.last[0]
      last_reader.each_line do |line|
        block.call(line.chomp)
      end
      last_reader.close

      # Wait for all children and collect statuses
      statuses = pids.map do |pid|
        Process.wait(pid)
        $?
      end
      @statuses = statuses
      @status = determine_pipeline_status(statuses)
      self
    end

    def determine_pipeline_status(statuses)
      return statuses.last unless Builtins.set_option?('pipefail')

      # With pipefail, return rightmost non-zero exit status
      failed = statuses.reverse.find { |s| !s.success? }
      failed || statuses.last
    end
  end

  class Subshell
    attr_reader :status
    attr_accessor :stdin, :stdout, :stderr

    def initialize(&block)
      @block = block
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @ran = false
    end

    def ran?
      @ran
    end

    def success?
      @status&.success? || false
    end

    def run
      return self if @ran
      @ran = true

      if @noclobber_failed
        @status = NoclobberStatus.new
        return self
      end

      if @restricted_failed
        @status = RestrictedStatus.new
        return self
      end

      pid = fork do
        $stdin.reopen(@stdin) if @stdin
        $stdout.reopen(@stdout) if @stdout
        if @stderr == :stdout
          $stderr.reopen($stdout)
        elsif @stderr
          $stderr.reopen(@stderr)
        end

        # The block contains __run_cmd calls which handle execution
        # So we just call the block and check the result's status
        result = @block.call

        exit_code = if result.respond_to?(:success?)
                      result.success? ? 0 : 1
                    else
                      0
                    end
        exit(exit_code)
      end

      @stdin&.close unless @stdin == $stdin || @stdin.is_a?(Symbol)
      @stdout&.close unless @stdout == $stdout || @stdout.is_a?(Symbol)

      Process.wait(pid)
      @status = $?
      self
    end

    def |(other)
      Pipeline.new(self, other)
    end

    def redirect_out(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      if Builtins.set_option?('C') && File.exist?(file)
        $stderr.puts "rubish: #{file}: cannot overwrite existing file"
        @noclobber_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      self
    end

    def redirect_clobber(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      self
    end

    def redirect_append(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stdout = File.open(file, 'a')
      self
    end

    def redirect_in(file)
      @stdin = File.open(file, 'r')
      self
    end

    def redirect_err(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stderr = File.open(file, 'w')
      self
    end

    def redirect_err_to_out
      @stderr = :stdout
      self
    end

    def dup_out(target)
      case target
      when '1' then self
      when '2' then @stdout = :stderr; self
      when '-' then @stdout = :closed; self
      else redirect_out(target)
      end
    end

    def dup_in(target)
      case target
      when '0' then self
      when '-' then @stdin = :closed; self
      else redirect_in(target)
      end
    end
  end

  # Wrapper for heredoc/herestring that provides content as stdin
  class HeredocCommand
    attr_reader :status
    attr_accessor :stdin, :stdout, :stderr

    def initialize(content, &block)
      @content = content
      @block = block
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @ran = false
    end

    def ran?
      @ran
    end

    def success?
      @status&.success? || false
    end

    def run
      return self if @ran
      @ran = true

      if @noclobber_failed
        @status = NoclobberStatus.new
        return self
      end

      if @restricted_failed
        @status = RestrictedStatus.new
        return self
      end

      cmd = @block.call
      if cmd.is_a?(Command) || cmd.is_a?(Pipeline)
        # Create a pipe for heredoc content
        reader, writer = IO.pipe
        writer.write(@content)
        writer.close

        # Set stdin from heredoc content
        cmd.stdin = reader

        # Apply any additional redirects we have
        cmd.stdout = @stdout if @stdout
        cmd.stderr = @stderr if @stderr

        cmd.run
        reader.close unless reader.closed?
        @status = cmd.status
      end
      self
    end

    def |(other)
      Pipeline.new(self, other)
    end

    def redirect_out(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      if Builtins.set_option?('C') && File.exist?(file)
        $stderr.puts "rubish: #{file}: cannot overwrite existing file"
        @noclobber_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      self
    end

    def redirect_clobber(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      self
    end

    def redirect_append(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stdout = File.open(file, 'a')
      self
    end

    def redirect_in(file)
      # For heredoc, stdin comes from content, so this is ignored
      self
    end

    def redirect_err(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stderr = File.open(file, 'w')
      self
    end

    def redirect_err_to_out
      @stderr = :stdout
      self
    end

    def dup_out(target)
      case target
      when '1' then self
      when '2' then @stdout = :stderr; self
      when '-' then @stdout = :closed; self
      else redirect_out(target)
      end
    end

    def dup_in(target)
      case target
      when '0' then self
      when '-' then @stdin = :closed; self
      else redirect_in(target)
      end
    end
  end
end
