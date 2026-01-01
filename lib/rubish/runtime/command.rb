# frozen_string_literal: true

module Rubish
  class Command
    attr_reader :name, :args, :pid, :status
    attr_accessor :stdin, :stdout, :stderr

    def initialize(name, *args)
      @name = name
      @args = args
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @ran = false
    end

    def ran?
      @ran
    end

    def run
      return self if @ran
      @ran = true

      @pid = fork do
        $stdin.reopen(@stdin) if @stdin
        $stdout.reopen(@stdout) if @stdout
        $stderr.reopen(@stderr) if @stderr
        exec(name, *args)
      end

      @stdin&.close unless @stdin == $stdin
      @stdout&.close unless @stdout == $stdout

      Process.wait(@pid)
      @status = $?
      self
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
  end

  class Pipeline
    attr_reader :commands, :status

    def initialize(*commands)
      @commands = commands.flatten
      @ran = false
    end

    def |(other)
      @commands << other
      self
    end

    def ran?
      @ran
    end

    def run
      return self if @ran
      @ran = true

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
          exec(cmd.name, *cmd.args)
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
  end
end
