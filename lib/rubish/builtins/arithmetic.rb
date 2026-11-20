# frozen_string_literal: true

require_relative '../arithmetic_evaluator'

module Rubish
  module Builtins
    def let(args)
      # let expression [expression ...]
      # Evaluates arithmetic expressions
      # Returns 0 (true) if last expression is non-zero, 1 (false) if zero

      if args.empty?
        puts 'let: usage: let expression [expression ...]'
        return false
      end

      last_result = 0

      args.each do |expr|
        last_result = evaluate_arithmetic(expr)
      end

      # Return true if last result is non-zero (shell convention)
      last_result != 0
    rescue ArithmeticEvaluator::Error => e
      $stderr.puts "rubish: let: #{e.message}"
      false
    end

    # Evaluate one `let` expression. Assignments write through to ENV, as
    # let's variables have always been environment-backed here.
    def evaluate_arithmetic(expr)
      let_evaluator.evaluate(expr).to_i
    end

    def let_evaluator
      @let_evaluator ||= ArithmeticEvaluator.new(
        get_var: ->(name) { get_var(name) },
        set_var: lambda do |name, value|
          if readonly?(name)
            puts "let: #{name}: readonly variable"
          else
            ENV[name] = value
            @state.shell_vars[name] = value if @state.shell_vars.key?(name)
          end
        end,
        get_array_element: ->(name, index) { get_array_element(name, index) },
        set_array_element: ->(name, index, value) { set_array_element(name, index, value) },
        var_set: ->(name) { var_set?(name) }
      )
    end
  end
end
