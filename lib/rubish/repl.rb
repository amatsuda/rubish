# frozen_string_literal: true

require 'reline'

module Rubish
  class REPL
    def initialize
      @lexer_class = Lexer
      @parser_class = Parser
      @codegen = Codegen.new
      @last_line = nil
    end

    def run
      setup_reline
      setup_signals
      exit_code = catch(:exit) do
        loop { process_line }
      end
      exit_code
    end

    private

    def setup_reline
      Reline.completion_proc = ->(input) { complete(input) }
    end

    def setup_signals
      # Ignore SIGINT and SIGTSTP in the shell itself
      # They should only affect foreground jobs
      trap('INT') { puts }   # Just print newline on Ctrl+C
      trap('TSTP') { }       # Ignore Ctrl+Z for shell
    end

    def prompt
      "#{Dir.pwd.sub(ENV['HOME'], '~')}$ "
    end

    def process_line
      # Check for completed background jobs
      JobManager.instance.check_background_jobs

      line = Reline.readline(prompt, true)
      return throw(:exit, 0) unless line

      line = line.strip
      return if line.empty?

      @last_line = line
      execute(line)
    rescue Interrupt
      puts
    rescue => e
      puts "rubish: #{e.message}"
    end

    def execute(line)
      tokens = @lexer_class.new(line).tokenize
      ast = @parser_class.new(tokens).parse
      return unless ast

      # Check for builtins (simple command only)
      if ast.is_a?(AST::Command) && Builtins.builtin?(ast.name)
        Builtins.run(ast.name, ast.args)
        return
      end

      code = @codegen.generate(ast)
      eval_in_context(code)
    end

    def eval_in_context(code)
      result = binding.eval(code)
      result.run if result.is_a?(Command) || result.is_a?(Pipeline)
      result
    end

    def __cmd(name, *args, &block)
      Command.new(name, *args, &block)
    end

    def __background(&block)
      # Fork and run in background
      pid = fork do
        # Reset signal handlers in child
        trap('INT', 'DEFAULT')
        trap('TSTP', 'DEFAULT')

        # Create new process group
        Process.setpgid(0, 0)

        # Execute the command
        result = block.call
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)
        exit(0)
      end

      # Parent: create job and return immediately
      Process.setpgid(pid, pid) rescue nil  # May fail if child already set it
      job = JobManager.instance.add(
        pid: pid,
        pgid: pid,
        command: @last_line
      )
      puts "[#{job.id}] #{pid}"
      nil
    end

    def complete(input)
      line = Reline.line_buffer
      is_first_word = !line.include?(' ') || line.end_with?('| ')

      if is_first_word
        complete_command(input)
      else
        complete_file(input)
      end
    end

    def complete_command(input)
      results = []

      # Builtins
      Builtins::COMMANDS.each do |cmd|
        results << cmd if cmd.start_with?(input)
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
      Dir.glob("#{input}*").map do |f|
        File.directory?(f) ? "#{f}/" : f
      end.sort
    end
  end
end
