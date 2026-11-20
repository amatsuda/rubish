# frozen_string_literal: true

require_relative 'arithmetic_evaluator'

module Rubish
  # Arithmetic evaluation for the shell REPL: $(( )), (( )), arithmetic for
  # loops, `declare -i` assignments and array subscripts. This is a thin
  # adapter between the shell's variable store and ArithmeticEvaluator,
  # which does the parsing without ever calling Ruby's eval.
  #
  # Bad input raises ArithmeticEvaluator::Error; REPL#execute reports it
  # like bash and sets $? to 1.
  module Arithmetic
    # Shell arithmetic is integer-valued: floats may appear inside an
    # expression (zsh-style maths functions) but the result is truncated
    def eval_arithmetic_expr(expr)
      result = arithmetic_evaluator.evaluate(expr)
      result.is_a?(Float) ? result.to_i : result
    end

    def arithmetic_evaluator
      @arithmetic_evaluator ||= ArithmeticEvaluator.new(
        get_var: ->(name) { get_special_var(name) || Builtins.get_var(name) },
        set_var: ->(name, value) { Builtins.set_var(name, value) },
        get_array_element: ->(name, index) { Builtins.get_array_element(name, index) },
        set_array_element: ->(name, index, value) { Builtins.set_array_element(name, index, value) },
        positional: ->(n) { (@positional_params || [])[n - 1] },
        var_set: ->(name) { Builtins.var_set?(name) },
        subst: ->(cmd) { __run_subst(cmd) }
      )
    end
  end
end
