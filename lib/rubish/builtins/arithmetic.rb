# frozen_string_literal: true

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
    end

    def evaluate_arithmetic(expr)
      # Handle assignment operators (but not ==, !=, <=, >=)
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\s*([\+\-\*\/%]?=)(?!=)\s*(.+)\z/
        var_name = $1
        operator = $2
        value_expr = $3

        # Check readonly
        if readonly?(var_name)
          puts "let: #{var_name}: readonly variable"
          return 0
        end

        # Evaluate the right side
        value = evaluate_arithmetic_expr(value_expr)

        if operator == '='
          # Simple assignment
          ENV[var_name] = value.to_s
        else
          # Compound assignment (+=, -=, *=, /=, %=)
          current = (ENV[var_name] || '0').to_i
          case operator
          when '+='
            ENV[var_name] = (current + value).to_s
          when '-='
            ENV[var_name] = (current - value).to_s
          when '*='
            ENV[var_name] = (current * value).to_s
          when '/='
            ENV[var_name] = (value.zero? ? 0 : current / value).to_s
          when '%='
            ENV[var_name] = (value.zero? ? 0 : current % value).to_s
          end
        end

        return ENV[var_name].to_i
      end

      # Handle increment/decrement operators
      if expr =~ /\A\+\+([a-zA-Z_][a-zA-Z0-9_]*)\z/
        # Pre-increment
        var_name = $1
        return 0 if readonly?(var_name)
        val = (ENV[var_name] || '0').to_i + 1
        ENV[var_name] = val.to_s
        return val
      end

      if expr =~ /\A--([a-zA-Z_][a-zA-Z0-9_]*)\z/
        # Pre-decrement
        var_name = $1
        return 0 if readonly?(var_name)
        val = (ENV[var_name] || '0').to_i - 1
        ENV[var_name] = val.to_s
        return val
      end

      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\+\+\z/
        # Post-increment
        var_name = $1
        return 0 if readonly?(var_name)
        old_val = (ENV[var_name] || '0').to_i
        ENV[var_name] = (old_val + 1).to_s
        return old_val
      end

      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)--\z/
        # Post-decrement
        var_name = $1
        return 0 if readonly?(var_name)
        old_val = (ENV[var_name] || '0').to_i
        ENV[var_name] = (old_val - 1).to_s
        return old_val
      end

      # Just evaluate the expression
      evaluate_arithmetic_expr(expr)
    end

    def evaluate_arithmetic_expr(expr)
      # Replace variable references with their values
      # Handle $VAR, ${VAR}, and bare variable names
      expanded = expr.gsub(/\$\{([^}]+)\}|\$([a-zA-Z_][a-zA-Z0-9_]*)|([a-zA-Z_][a-zA-Z0-9_]*)/) do |match|
        if $1
          # ${VAR} form
          (ENV[$1] || '0')
        elsif $2
          # $VAR form
          (ENV[$2] || '0')
        elsif $3
          # Plain variable name - in arithmetic context, unset vars default to 0
          (ENV[$3] || '0')
        else
          match
        end
      end

      # Handle comparison operators (convert to Ruby equivalents)
      expanded = expanded.gsub('==', '==')
      expanded = expanded.gsub('!=', '!=')
      expanded = expanded.gsub('<=', '<=')
      expanded = expanded.gsub('>=', '>=')

      # Handle logical operators
      expanded = expanded.gsub('&&', ' && ')
      expanded = expanded.gsub('||', ' || ')
      expanded = expanded.gsub(/!(?!=)/, ' !')

      # Handle ternary operator
      expanded = expanded.gsub('?', ' ? ').gsub(':', ' : ')

      # Evaluate safely
      begin
        result = Kernel.eval(expanded)
        result.is_a?(Integer) ? result : (result ? 1 : 0)
      rescue StandardError
        0
      end
    end
  end
end
