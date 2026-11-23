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
      result = arithmetic_evaluator.evaluate(expand_arith_parameters(expr))
      result.is_a?(Float) ? result.to_i : result
    end

    # Bash expands the parameters in an arithmetic expression as text
    # before evaluating it. The evaluator reads `$name`, `$N` and `$(cmd)`
    # itself; the braced forms (`${#arr[@]}`, `${u:-0}`), the specials
    # `$#`, `$?`, `$$`, `$!`, and a `$name` right after a base prefix
    # (`10#$x`) are expanded here.
    def expand_arith_parameters(expr)
      return expr unless expr.include?('$')

      out = +''
      i = 0
      while i < expr.length
        c = expr[i]
        if c == '$' && expr[i + 1] == '{' && (close = matching_brace_in(expr, i + 1))
          out << expand_string_content(expr[i..close])
          i = close + 1
        elsif c == '$' && '#?$!'.include?(expr[i + 1].to_s)
          out << expand_string_content(expr[i, 2])
          i += 2
        elsif c == '#' && expr[i + 1] == '$' && expr[i + 2].to_s.match?(/[a-zA-Z_0-9]/)
          j = i + 2
          j += 1 while j < expr.length && expr[j].match?(/[a-zA-Z0-9_]/)
          out << '#' << expand_string_content(expr[(i + 1)...j])
          i = j
        else
          out << c
          i += 1
        end
      end
      out
    end

    def matching_brace_in(str, open_pos)
      depth = 0
      (open_pos...str.length).each do |k|
        depth += 1 if str[k] == '{'
        depth -= 1 if str[k] == '}'
        return k if depth == 0
      end
      nil
    end

    def arithmetic_evaluator
      @arithmetic_evaluator ||= ArithmeticEvaluator.new(
        get_var: lambda { |name|
          value = get_special_var(name) || Builtins.get_var(name)
          if value.nil? && Builtins.set_option?('u') && !Builtins.array?(name)
            $stderr.puts Builtins.format_error('unbound variable', command: name)
            raise NounsetError, "#{name}: unbound variable"
          end
          value
        },
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
