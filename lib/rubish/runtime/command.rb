# frozen_string_literal: true

module Rubish
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

  class Command
    attr_reader :name, :pid, :status
    attr_accessor :stdin, :stdout, :stderr, :block

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

    def initialize(name, *args, &block)
      @name = name
      @args = expand_args(args)
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @block = block
      @ran = false
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
      # Force overwrite even with noclobber (>|)
      @stdout = File.open(file, 'w')
      self
    end

    def redirect_append(file)
      @stdout = File.open(file, 'a')
      self
    end

    def redirect_in(file)
      @stdin = File.open(file, 'r')
      self
    end

    def redirect_err(file)
      @stderr = File.open(file, 'w')
      self
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
      # Resolve command path before forking (so hash updates are visible in parent)
      cmd_path = resolve_command_path(name)

      # Extract keyword assignments if -k is set
      cmd_args, keyword_env = extract_keyword_assignments(@args)

      @pid = fork do
        $stdin.reopen(@stdin) if @stdin
        $stdout.reopen(@stdout) if @stdout
        $stderr.reopen(@stderr) if @stderr

        # Set keyword environment variables
        keyword_env.each { |k, v| ENV[k] = v }

        # Check if this is a user-defined function
        if Command.function?(name)
          result = Command.call_function(name, cmd_args)
          exit(result ? 0 : 1)
        else
          exec(cmd_path, *cmd_args)
        end
      end

      @stdin&.close unless @stdin == $stdin
      @stdout&.close unless @stdout == $stdout

      Process.wait(@pid)
      @status = $?
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
        $stderr.reopen(@stderr) if @stderr

        # Set keyword environment variables
        keyword_env.each { |k, v| ENV[k] = v }

        exec(cmd_path, *cmd_args)
      end

      writer.close
      @stdin&.close unless @stdin == $stdin

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
      return cached if cached && !Builtins.execignore?(cached)

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

    private

    def run_simple
      # Set up pipes between commands
      pipes = (@commands.length - 1).times.map { IO.pipe }

      pids = @commands.each_with_index.map do |cmd, i|
        # Set stdin from previous pipe (except first command)
        cmd.stdin ||= pipes[i - 1][0] if i > 0

        # Set stdout to next pipe (except last command)
        cmd.stdout ||= pipes[i][1] if i < @commands.length - 1

        fork do
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
            exec(cmd.name, *cmd.args)
          end
        end
      end

      # Parent closes all pipe ends
      pipes.each do |reader, writer|
        reader.close
        writer.close
      end

      # Wait for all children and collect statuses
      statuses = pids.map do |pid|
        Process.wait(pid)
        $?
      end
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
            exec(cmd.name, *cmd.args)
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

      pid = fork do
        $stdin.reopen(@stdin) if @stdin
        $stdout.reopen(@stdout) if @stdout
        $stderr.reopen(@stderr) if @stderr

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

      @stdin&.close unless @stdin == $stdin
      @stdout&.close unless @stdout == $stdout

      Process.wait(pid)
      @status = $?
      self
    end

    def |(other)
      Pipeline.new(self, other)
    end

    def redirect_out(file)
      if Builtins.set_option?('C') && File.exist?(file)
        $stderr.puts "rubish: #{file}: cannot overwrite existing file"
        @noclobber_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      self
    end

    def redirect_clobber(file)
      @stdout = File.open(file, 'w')
      self
    end

    def redirect_append(file)
      @stdout = File.open(file, 'a')
      self
    end

    def redirect_in(file)
      @stdin = File.open(file, 'r')
      self
    end

    def redirect_err(file)
      @stderr = File.open(file, 'w')
      self
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
      if Builtins.set_option?('C') && File.exist?(file)
        $stderr.puts "rubish: #{file}: cannot overwrite existing file"
        @noclobber_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      self
    end

    def redirect_clobber(file)
      @stdout = File.open(file, 'w')
      self
    end

    def redirect_append(file)
      @stdout = File.open(file, 'a')
      self
    end

    def redirect_in(file)
      # For heredoc, stdin comes from content, so this is ignored
      self
    end

    def redirect_err(file)
      @stderr = File.open(file, 'w')
      self
    end
  end
end
