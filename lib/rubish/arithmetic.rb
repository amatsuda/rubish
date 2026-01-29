# frozen_string_literal: true

module Rubish
  # Arithmetic evaluation helpers for the shell REPL
  # Handles $(( )), (( )), and arithmetic for loops
  module Arithmetic
    def eval_arithmetic_expr(expr)
      # Handle comma-separated expressions (evaluate all, return last)
      # Be careful not to split inside parentheses
      expressions = split_arithmetic_expressions(expr)
      result = 0

      expressions.each do |e|
        e = e.strip
        next if e.empty?

        result = eval_single_arithmetic(e)
      end

      result
    end

    def split_arithmetic_expressions(expr)
      # Split by comma, but not inside parentheses
      result = []
      current = +''
      depth = 0

      expr.each_char do |c|
        case c
        when '('
          depth += 1
          current << c
        when ')'
          depth -= 1
          current << c
        when ','
          if depth == 0
            result << current
            current = +''
          else
            current << c
          end
        else
          current << c
        end
      end

      result << current unless current.empty?
      result
    end

    def eval_single_arithmetic(expr)
      # Handle pre-increment/decrement: ++var, --var
      if expr =~ /\A\+\+([a-zA-Z_][a-zA-Z0-9_]*)\z/
        var = $1
        val = (Builtins.get_var(var) || '0').to_i + 1
        Builtins.set_var(var, val.to_s)
        return val
      end

      if expr =~ /\A--([a-zA-Z_][a-zA-Z0-9_]*)\z/
        var = $1
        val = (Builtins.get_var(var) || '0').to_i - 1
        Builtins.set_var(var, val.to_s)
        return val
      end

      # Handle post-increment/decrement: var++, var--
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\+\+\z/
        var = $1
        old_val = (Builtins.get_var(var) || '0').to_i
        Builtins.set_var(var, (old_val + 1).to_s)
        return old_val
      end

      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)--\z/
        var = $1
        old_val = (Builtins.get_var(var) || '0').to_i
        Builtins.set_var(var, (old_val - 1).to_s)
        return old_val
      end

      # Handle compound assignments: var+=, var-=, var*=, var/=, var%=, var<<=, var>>=, var&=, var|=, var^=
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\s*(\+|-|\*|\/|%|<<|>>|&|\||\^)=\s*(.+)\z/
        var, op, rhs = $1, $2, $3
        lhs_val = (Builtins.get_var(var) || '0').to_i
        rhs_val = eval_single_arithmetic(rhs)
        result = case op
                 when '+' then lhs_val + rhs_val
                 when '-' then lhs_val - rhs_val
                 when '*' then lhs_val * rhs_val
                 when '/' then rhs_val != 0 ? lhs_val / rhs_val : 0
                 when '%' then rhs_val != 0 ? lhs_val % rhs_val : 0
                 when '<<' then lhs_val << rhs_val
                 when '>>' then lhs_val >> rhs_val
                 when '&' then lhs_val & rhs_val
                 when '|' then lhs_val | rhs_val
                 when '^' then lhs_val ^ rhs_val
                 end
        Builtins.set_var(var, result.to_s)
        return result
      end

      # Handle simple assignment: var=expr (but not == comparison)
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(?!=)(.+)\z/
        var, rhs = $1, $2
        result = eval_single_arithmetic(rhs)
        Builtins.set_var(var, result.to_s)
        return result
      end

      # Regular arithmetic expression - evaluate directly to handle booleans
      # Expand variables first
      expanded = expr.gsub(/\$\{([^}]+)\}|\$(\d+)|\$([a-zA-Z_][a-zA-Z0-9_]*)|([a-zA-Z_][a-zA-Z0-9_]*)/) do |match|
        if $2 # Positional parameter like $1, $2
          n = $2.to_i
          (@positional_params[n - 1] || '0')
        elsif (var_name = $1 || $3 || $4)
          get_special_var(var_name) || Builtins.get_var(var_name) || '0'
        else
          match
        end
      end

      begin
        result = Kernel.eval(expanded)
        # Handle boolean results (comparison operators return true/false in Ruby)
        case result
        when true then 1
        when false then 0
        when Numeric then result.to_i
        else result.to_s.to_i
        end
      rescue StandardError
        0
      end
    end
  end
end
