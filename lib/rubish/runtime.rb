# frozen_string_literal: true

module Rubish
  # Runtime methods called from generated Ruby code (codegen output)
  # Methods in this module have __ prefix and are the interface between
  # codegen and the shell execution
  module Runtime
    # === Arithmetic methods ===

    def __arith_for_loop(init_expr, cond_expr, update_expr, &block)
      # C-style arithmetic for loop: for ((init; cond; update)); do body; done
      # Evaluate init expression once
      eval_arithmetic_expr(init_expr) unless init_expr.empty?

      # Loop while condition is true (non-zero)
      loop do
        # If condition is empty, it's always true (infinite loop)
        unless cond_expr.empty?
          result = eval_arithmetic_expr(cond_expr)
          break if result == 0  # Condition is false
        end

        # Execute body
        block.call

        # Evaluate update expression
        eval_arithmetic_expr(update_expr) unless update_expr.empty?
      end
    end

    def __arith(expr)
      # Evaluate arithmetic expression
      # Replace variable references with their values
      # Also handle positional parameters like $1, $2, etc.
      expanded = expr.gsub(/\$\{([^}]+)\}|\$(\d+)|\$([a-zA-Z_][a-zA-Z0-9_]*)|([a-zA-Z_][a-zA-Z0-9_]*)/) do |match|
        if $2 # Positional parameter like $1, $2
          n = $2.to_i
          (@positional_params[n - 1] || '0')
        elsif (var_name = $1 || $3 || $4)
          # Use get_special_var for special variables, fall back to ENV
          get_special_var(var_name) || ENV.fetch(var_name, '0')
        else
          match
        end
      end

      # Evaluate the expression safely (only allow arithmetic)
      # Convert shell operators to Ruby: ** for exponentiation is same
      # Note: bash uses ** for exponent, which Ruby also supports
      begin
        result = Kernel.eval(expanded)
        result.to_s
      rescue StandardError
        '0'
      end
    end

    def __arithmetic_command(expr)
      # Evaluate (( )) arithmetic command
      # Returns exit status 0 if result is non-zero, 1 if result is zero
      # Supports variable assignments like x=1, x++, x--, ++x, --x, x+=1, etc.
      result = eval_arithmetic_expr(expr)
      ExitStatus.new(result != 0 ? 0 : 1)
    end
  end
end
