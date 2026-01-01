# frozen_string_literal: true

module Rubish
  # Simple exit status for builtins
  ExitStatus = Struct.new(:exitstatus) do
    def success?
      exitstatus == 0
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
      @pid = fork do
        $stdin.reopen(@stdin) if @stdin
        $stdout.reopen(@stdout) if @stdout
        $stderr.reopen(@stderr) if @stderr

        # Check if this is a user-defined function
        if Command.function?(name)
          Command.call_function(name, @args)
          exit(0)
        else
          exec(name, *@args)
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

      @pid = fork do
        reader.close
        $stdin.reopen(@stdin) if @stdin
        $stdout.reopen(writer)
        $stderr.reopen(@stderr) if @stderr
        exec(name, *@args)
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
  end

  class Pipeline
    attr_reader :commands, :status
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

          # Check if this is a user-defined function
          if Command.function?(cmd.name)
            Command.call_function(cmd.name, cmd.args)
            exit(0)
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

      # Wait for all children
      pids.each { |pid| Process.wait(pid) }
      @status = $?
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

          # Check if this is a user-defined function
          if Command.function?(cmd.name)
            Command.call_function(cmd.name, cmd.args)
            exit(0)
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

      # Wait for all children
      pids.each { |pid| Process.wait(pid) }
      @status = $?
      self
    end
  end
end
