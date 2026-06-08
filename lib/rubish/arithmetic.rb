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
          elsif braced =~ /\A\+([a-zA-Z_][a-zA-Z0-9_]*)\z/
            # ${+VAR}: zsh parameter-is-set test. starship's precmd uses
            # `(( ${+STARSHIP_START_TIME} ))` to gate duration tracking,
            # so this has to evaluate inside `(( … ))` too.
            Builtins.var_set?($1) ? '1' : '0'
          else
            get_special_var(braced) || Builtins.get_var(braced) || '0'
          end
        elsif (var_name = $3)
          subscript = $4
          if subscript
            resolve_array_element(var_name, subscript[1...-1])
          elsif !match.start_with?('$') && Regexp.last_match.post_match.start_with?('(')
            # Function call like `int(x)`, `rint(x)`: an identifier
            # immediately followed by `(` is a math function (zsh/mathfunc),
            # not a variable. Leave it untouched so eval can dispatch.
            match
          else
            get_special_var(var_name) || Builtins.get_var(var_name) || '0'
          end
        else
          match
        end
      end

      begin
        result = ARITH_FUNC_EVAL.instance_eval(expanded)
        # Handle boolean results (comparison operators return true/false in Ruby)
        case result
        when true then 1
        when false then 0
        when Numeric then result.to_i
        else result.to_s.to_i
        end
      rescue StandardError, SyntaxError
        0
      end
    end

    # Math functions exposed inside `(( … ))` and `$(( … ))`. These mirror
    # zsh/mathfunc — starship's `__starship_get_time` body
    # `(( STARSHIP_CAPTURED_TIME = int(rint(EPOCHREALTIME * 1000)) ))`
    # is the canonical reason this exists. The expression is evaluated
    # against an instance of this class so method dispatch resolves the
    # function names; Math constants and Ruby operators work as usual.
    class ArithFuncEvaluator
      def int(x); x.to_i; end
      def rint(x); x.round; end
      def floor(x); x.floor; end
      def ceil(x); x.ceil; end
      def abs(x); x.abs; end
      def sqrt(x); Math.sqrt(x); end
      def exp(x); Math.exp(x); end
      def log(x); Math.log(x); end
      def log2(x); Math.log2(x); end
      def log10(x); Math.log10(x); end
      def sin(x); Math.sin(x); end
      def cos(x); Math.cos(x); end
      def tan(x); Math.tan(x); end
      def asin(x); Math.asin(x); end
      def acos(x); Math.acos(x); end
      def atan(x); Math.atan(x); end
      def atan2(y, x); Math.atan2(y, x); end
    end
    ARITH_FUNC_EVAL = ArithFuncEvaluator.new
  end
end
