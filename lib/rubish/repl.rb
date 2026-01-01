# frozen_string_literal: true

require 'reline'

module Rubish
  class REPL
    def initialize
      @lexer_class = Lexer
      @parser_class = Parser
      @codegen = Codegen.new
    end

    def run
      setup_reline
      exit_code = catch(:exit) do
        loop { process_line }
      end
      exit_code
    end

    private

    def setup_reline
      Reline.completion_proc = ->(input) { complete(input) }
    end

    def prompt
      "#{Dir.pwd.sub(ENV['HOME'], '~')}$ "
    end

    def process_line
      line = Reline.readline(prompt, true)
      return throw(:exit, 0) unless line

      line = line.strip
      return if line.empty?

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
      Thread.new { block.call }
    end

    def complete(input)
      # File completion
      Dir.glob("#{input}*").map do |f|
        File.directory?(f) ? "#{f}/" : f
      end
    end
  end
end
