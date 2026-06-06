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

    def resolve_array_element(name, subscript)
      idx = eval_single_arithmetic(subscript)
      elem = Builtins.get_array_element(name, idx)
      elem.to_s.empty? ? '0' : elem.to_s
    end

    # Current value of an array element as an integer (unset/empty -> 0).
    def arith_elem_int(name, idx)
      v = Builtins.get_array_element(name, idx).to_s
      v.empty? ? 0 : v.to_i
    end

    # Apply a compound-assignment operator (+=, -=, ...) to two integers.
    def arith_binop(lhs, op, rhs)
      case op
      when '+' then lhs + rhs
      when '-' then lhs - rhs
      when '*' then lhs * rhs
      when '/' then rhs != 0 ? lhs / rhs : 0
      when '%' then rhs != 0 ? lhs % rhs : 0
      when '<<' then lhs << rhs
      when '>>' then lhs >> rhs
      when '&' then lhs & rhs
      when '|' then lhs | rhs
      when '^' then lhs ^ rhs
      end
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

    # Find the index of the first top-level occurrence of op (not inside parens).
    # Returns nil if not found.
    def find_top_level_op(expr, op)
      depth = 0
      op_len = op.length
      i = 0
      while i <= expr.length - op_len
        case expr[i]
        when '(' then depth += 1; i += 1
        when ')' then depth -= 1; i += 1
        else
          if depth == 0 && expr[i, op_len] == op
            return i
          end
          i += 1
        end
      end
      nil
    end

    # Return the index of the closing paren that matches expr[start] == '('.
    def find_matching_close(expr, start)
      depth = 0
      (start...expr.length).each do |i|
        case expr[i]
        when '(' then depth += 1
        when ')' then depth -= 1; return i if depth == 0
        end
      end
      nil
    end

    def eval_single_arithmetic(expr)
      expr = expr.strip

      # Strip outer parentheses: (expr) -> expr, but not (a)(b)
      if expr.start_with?('(')
        close = find_matching_close(expr, 0)
        if close == expr.length - 1
          return eval_single_arithmetic(expr[1...-1])
        end
      end

      # Short-circuit ||  (lower precedence than &&)
      if (pos = find_top_level_op(expr, '||'))
        left_val = eval_single_arithmetic(expr[0, pos])
        return left_val != 0 ? left_val : eval_single_arithmetic(expr[pos + 2..])
      end

      # Short-circuit &&
      if (pos = find_top_level_op(expr, '&&'))
        left_val = eval_single_arithmetic(expr[0, pos])
        return left_val == 0 ? 0 : eval_single_arithmetic(expr[pos + 2..])
      end

      # Logical not: ! expr  (bash: 0=false, non-zero=true, opposite of Ruby)
      if expr =~ /\A!\s*(.+)\z/
        return eval_single_arithmetic($1) == 0 ? 1 : 0
      end

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

      # Array-element assignment forms must be handled before the scalar ones:
      # the subscript makes `a[i]=v` fall through to Kernel.eval otherwise,
      # where `a[i]` expands to its value and `2 = 9` is a Ruby SyntaxError.

      # ++a[i] / --a[i]
      if expr =~ /\A(\+\+|--)([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\]\z/
        op, name, idx = $1, $2, eval_single_arithmetic($3)
        val = arith_elem_int(name, idx) + (op == '++' ? 1 : -1)
        Builtins.set_array_element(name, idx, val.to_s)
        return val
      end

      # a[i]++ / a[i]--
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\](\+\+|--)\z/
        name, idx, op = $1, eval_single_arithmetic($2), $3
        old = arith_elem_int(name, idx)
        Builtins.set_array_element(name, idx, (old + (op == '++' ? 1 : -1)).to_s)
        return old
      end

      # a[i] += expr (and -=, *=, /=, %=, <<=, >>=, &=, |=, ^=)
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\]\s*(\+|-|\*|\/|%|<<|>>|&|\||\^)=\s*(.+)\z/
        name, idx, op, rhs = $1, eval_single_arithmetic($2), $3, $4
        result = arith_binop(arith_elem_int(name, idx), op, eval_single_arithmetic(rhs))
        Builtins.set_array_element(name, idx, result.to_s)
        return result
      end

      # a[i] = expr (not == comparison)
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\]\s*=\s*(?!=)(.+)\z/
        name, idx, rhs = $1, eval_single_arithmetic($2), $3
        result = eval_single_arithmetic(rhs)
        Builtins.set_array_element(name, idx, result.to_s)
        return result
      end

      # Handle compound assignments: var+=, var-=, var*=, var/=, var%=, var<<=, var>>=, var&=, var|=, var^=
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\s*(\+|-|\*|\/|%|<<|>>|&|\||\^)=\s*(.+)\z/
        var, op, rhs = $1, $2, $3
        lhs_val = (Builtins.get_var(var) || '0').to_i
        result = arith_binop(lhs_val, op, eval_single_arithmetic(rhs))
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
      # Pre-convert hex literals so their letter chars don't get treated as variables
      expr = expr.gsub(/0[xX][0-9a-fA-F]+/) { |m| Integer(m).to_s }
      # Expand variables first. `arr[expr]` / `${arr[expr]}` / `$arr[expr]`
      # all refer to an indexed array element — recursively evaluate the
      # subscript, then look up the element. Bash uses the same rule
      # inside `(( ))` and `$(( ))`.
      expanded = expr.gsub(/\$\{([^}]+)\}|\$(\d+)|\$?([a-zA-Z_][a-zA-Z0-9_]*)(\[[^\]]+\])?/) do |match|
        if $2 # Positional parameter like $1, $2
          n = $2.to_i
          (@positional_params[n - 1] || '0')
        elsif (braced = $1)
          # ${var} or ${arr[expr]} (the latter only — already stripped by [^}]+)
          if braced =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[(.+)\]\z/
            resolve_array_element($1, $2)
          else
            get_special_var(braced) || Builtins.get_var(braced) || '0'
          end
        elsif (var_name = $3)
          subscript = $4
          if subscript
            resolve_array_element(var_name, subscript[1...-1])
          else
            get_special_var(var_name) || Builtins.get_var(var_name) || '0'
          end
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
