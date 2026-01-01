# frozen_string_literal: true

module Rubish
  class Command
    attr_reader :name, :args, :pid, :status

    def initialize(name, *args)
      @name = name
      @args = args
      @stdin = $stdin
      @stdout = $stdout
      @stderr = $stderr
      @ran = false
    end

    def ran?
      @ran
    end

    def run
      return self if @ran
      @ran = true
      @pid = fork do
        $stdin.reopen(@stdin) unless @stdin == $stdin
        $stdout.reopen(@stdout) unless @stdout == $stdout
        $stderr.reopen(@stderr) unless @stderr == $stderr
        exec(name, *args)
      end
      Process.wait(@pid)
      @status = $?
      self
    end

    def |(other)
      reader, writer = IO.pipe

      # Run self with stdout to pipe
      left = fork do
        reader.close
        $stdin.reopen(@stdin) unless @stdin == $stdin
        $stdout.reopen(writer)
        exec(name, *args)
      end
      writer.close

      # Set up other to read from pipe
      other.instance_variable_set(:@stdin, reader)
      result = other.run
      reader.close

      Process.wait(left)
      result
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
end
