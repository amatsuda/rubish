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

    # === Expansion methods ===

    # Run command substitution within rubish itself (not external shell)
    # This allows user-defined functions to be available in $() substitution
    # Forks a subprocess, captures stdout, and returns the output (with trailing newlines removed)
    def __run_subst(cmd)
      reader, writer = IO.pipe
      # inherit_errexit: if disabled, child should not inherit errexit (set -e)
      inherit_errexit = Builtins.shopt_enabled?('inherit_errexit')

      pid = fork do
        reader.close
        # Redirect stdout to the pipe using the constant STDOUT
        # This works even if $stdout has been redirected to a StringIO (for testing)
        STDOUT.reopen(writer)
        $stdout = STDOUT

        # Suppress stderr during completion to avoid spurious output on terminal
        if Builtins.in_completion_context?
          STDERR.reopen(File.open(File::NULL, 'w'))
          $stderr = STDERR
        end

        # Command substitution only inherits errexit when inherit_errexit is enabled
        Builtins.set_options['e'] = false unless inherit_errexit

        begin
          exit_code = catch(:exit) do
            execute(cmd, skip_history_expansion: true)
            @last_status
          end
          exit(exit_code || 0)
        rescue => e
          $stderr.puts "rubish: #{e.message}" unless Builtins.in_completion_context?
          exit(1)
        end
      end

      writer.close
      output = reader.read.chomp
      reader.close

      Process.wait(pid)
      @last_status = $?.exitstatus || 0
      output
    end

    # Parameter expansion operations
    # Operators:
    #   :-  Use default if unset or null
    #   -   Use default only if unset (null is fine)
    #   :=  Assign default if unset or null
    #   =   Assign default only if unset
    #   :+  Use value if set and non-null
    #   +   Use value if set (even if null)
    #   :?  Error if unset or null
    #   ?   Error only if unset
    #   #   Remove shortest prefix matching pattern
    #   ##  Remove longest prefix matching pattern
    #   %   Remove shortest suffix matching pattern
    #   %%  Remove longest suffix matching pattern
    def __param_expand(var_name, operator, operand)
      # extquote: when enabled, process $'...' and $"..." quoting in the operand
      operand = expand_extquote(operand) if Builtins.shopt_enabled?('extquote')

      value, is_set, is_null = get_param_expand_info(var_name)

      case operator
      when ':-' then is_null ? operand : value                    # ${var:-default}
      when '-' then is_set ? value : operand                      # ${var-default}
      when ':=' then is_null ? assign_default(var_name, operand) : value  # ${var:=default}
      when '=' then is_set ? value : assign_default(var_name, operand)    # ${var=default}
      when ':+' then is_null ? '' : operand                       # ${var:+value}
      when '+' then is_set ? operand : ''                         # ${var+value}
      when ':?'                                                   # ${var:?message}
        raise(operand.empty? ? "#{var_name}: parameter null or not set" : operand) if is_null
        value
      when '?'                                                    # ${var?message}
        raise(operand.empty? ? "#{var_name}: parameter not set" : operand) unless is_set
        value || ''
      when '#'                                                    # ${var#pattern}
        return '' if value.nil?
        pattern_to_regex(operand, :prefix, :shortest).match(value) { |m| value[m.end(0)..] } || value
      when '##'                                                   # ${var##pattern}
        return '' if value.nil?
        pattern_to_regex(operand, :prefix, :longest).match(value) { |m| value[m.end(0)..] } || value
      when '%' then value.nil? ? '' : remove_suffix(value, operand, :shortest)   # ${var%pattern}
      when '%%' then value.nil? ? '' : remove_suffix(value, operand, :longest)   # ${var%%pattern}
      else value || ''
      end
    end

    # ${#var} - length of variable value
    def __param_length(var_name)
      (get_special_var(var_name) || Builtins.get_var(var_name) || '').length.to_s
    end

    # ${var:offset} or ${var:offset:length} - substring extraction
    def __param_substring(var_name, offset, length)
      value = get_special_var(var_name) || Builtins.get_var(var_name) || ''
      offset = offset.to_i
      if length
        length = length.to_i
        # Negative length means from end
        length < 0 ? value[offset...length] : value[offset, length]
      else
        value[offset..]
      end || ''
    end

    # ${var@operator} - transformation operators
    # Q: Quote for reuse as input
    # E: Expand escape sequences like $'...'
    # P: Expand as prompt string (PS1-style)
    # A: Assignment statement form
    # a: Attribute flags
    # U: Uppercase entire value
    # u: Uppercase first character
    # L: Lowercase entire value
    # K: For associative arrays, show key-value pairs
    def __param_transform(var_name, operator)
      value = get_special_var(var_name) || Builtins.get_var(var_name)

      case operator
      when 'Q' then value.nil? ? "''" : "'" + value.gsub("'") { "'\\''" } + "'"
      when 'E' then value.nil? ? '' : Builtins.process_escape_sequences(value)
      when 'P' then value.nil? ? '' : expand_prompt(value)
      when 'A'
        if value.nil?
          "declare -- #{var_name}"
        else
          prefix = Builtins.exported?(var_name) ? 'declare -x' : 'declare --'
          "#{prefix} #{var_name}=#{__param_transform(var_name, 'Q')}"
        end
      when 'a'
        flags = +''
        flags << 'x' if Builtins.exported?(var_name)
        flags << 'r' if Builtins.readonly?(var_name)
        flags
      when 'U' then value&.upcase || ''
      when 'u' then value.nil? || value.empty? ? '' : value[0].upcase + (value[1..] || '')
      when 'L' then value&.downcase || ''
      when 'K' then value.nil? ? "''" : __param_transform(var_name, 'Q')
      else value || ''
      end
    end

    # ${var/pattern/replacement} or ${var//pattern/replacement}
    # /  - replace first occurrence
    # // - replace all occurrences
    def __param_replace(var_name, operator, pattern, replacement)
      value = get_special_var(var_name) || Builtins.get_var(var_name) || ''
      return '' if value.empty?

      regex = pattern_to_regex(pattern, :any, :longest)
      replacement_proc = build_replacement_proc(replacement)

      case operator
      when '//' then replacement_proc ? value.gsub(regex, &replacement_proc) : value.gsub(regex, replacement)
      when '/' then replacement_proc ? value.sub(regex, &replacement_proc) : value.sub(regex, replacement)
      else value
      end
    end

    # Case modification operators
    # ^  - uppercase first character (if matches pattern)
    # ^^ - uppercase all characters (matching pattern)
    # ,  - lowercase first character (if matches pattern)
    # ,, - lowercase all characters (matching pattern)
    def __param_case(var_name, operator, pattern)
      value = Builtins.get_var(var_name) || ''
      return '' if value.empty?

      case operator
      when '^^' then apply_case_transform(value, pattern, :upcase, :all)
      when '^' then apply_case_transform(value, pattern, :upcase, :first)
      when ',,' then apply_case_transform(value, pattern, :downcase, :all)
      when ',' then apply_case_transform(value, pattern, :downcase, :first)
      else value
      end
    end

    # ${!var} - indirect expansion: get value of variable whose name is in var
    def __param_indirect(var_name)
      indirect_name = Builtins.get_var(var_name)
      return '' if indirect_name.nil? || indirect_name.empty?
      Builtins.get_var(indirect_name) || ''
    end

    # $"string" - locale-specific translation using TEXTDOMAIN
    # Uses gettext if available, otherwise returns original string
    def __translate(string)
      # noexpand_translation: do not expand $"..." strings for translation
      return string if Builtins.shopt_enabled?('noexpand_translation')

      textdomain = ENV['TEXTDOMAIN']
      return string if textdomain.nil? || textdomain.empty?

      begin
        require 'gettext'
        textdomaindir = ENV['TEXTDOMAINDIR']
        textdomaindir && !textdomaindir.empty? ? GetText.bindtextdomain(textdomain, path: textdomaindir) : GetText.bindtextdomain(textdomain)
        GetText._(string)
      rescue LoadError, StandardError
        string
      end
    end

    # ${arr[n]} or ${map[key]} - get array/assoc element
    # For associative arrays, index is expanded as string (key lookup)
    # For indexed arrays, index is evaluated as arithmetic expression
    def __array_element(var_name, index)
      expanded_index = expand_array_index(var_name, index)

      # Check special arrays first
      values = get_special_array_values(var_name)
      if values
        return get_special_assoc_value(var_name, expanded_index) if values == :assoc
        idx = safe_eval_index(expanded_index)
        return (values[idx] || '').to_s
      end

      if Builtins.assoc_array?(var_name)
        Builtins.get_assoc_element(var_name, expanded_index)
      else
        Builtins.get_array_element(var_name, safe_eval_index(expanded_index))
      end
    end

    # ${arr[@]} or ${arr[*]} - get all array/assoc values
    # @ mode: elements joined by space
    # * mode: elements joined by first character of IFS
    def __array_all(var_name, mode)
      values = get_special_array_values(var_name)
      values = case values
               when Array then values.map(&:to_s)
               when :assoc then get_special_assoc_all_values(var_name)
               when nil
                 if Builtins.assoc_array?(var_name)
                   Builtins.assoc_values(var_name)
                 else
                   Builtins.get_array(var_name).compact
                 end
               else values
               end

      mode == '@' ? values.join(' ') : Builtins.join_by_ifs(values)
    end

    # ${#arr[@]} - get array/assoc length
    def __array_length(var_name)
      values = get_special_array_values(var_name)
      length = case values
               when Array then values.length
               when :assoc then get_special_assoc_length(var_name)
               when nil
                 Builtins.assoc_array?(var_name) ? Builtins.assoc_length(var_name) : Builtins.array_length(var_name)
               else values.length
               end
      length.to_s
    end

    # ${!arr[@]} - get array indices or assoc keys
    def __array_keys(var_name)
      values = get_special_array_values(var_name)
      keys = case values
             when Array then (0...values.length).to_a
             when :assoc then get_special_assoc_keys(var_name)
             when nil
               if Builtins.assoc_array?(var_name)
                 Builtins.assoc_keys(var_name)
               else
                 arr = Builtins.get_array(var_name)
                 arr.each_index.select { |i| !arr[i].nil? }
               end
             else (0...values.length).to_a
             end
      keys.join(' ')
    end
  end
end
