# frozen_string_literal: true

module Rubish
  module Builtins
    ECHO_STOP_OUTPUT = "\x00STOP_OUTPUT\x00"

    def echo(args)
      # Handle string argument (from Ruby code like echo("hello"))
      args = [args] if args.is_a?(String)
      newline = true
      # xpg_echo: expand backslash escapes by default when enabled
      interpret_escapes = shopt_enabled?('xpg_echo')
      start_idx = 0

      # Parse options: -n (no newline), -e (enable escapes), -E (disable escapes)
      # Options can be combined like -ne, -en, -neE, etc.
      while start_idx < args.length && args[start_idx]&.start_with?('-') && args[start_idx] != '-'
        opt = args[start_idx]
        # Check if it's a valid option string (only contains n, e, E after -)
        break unless opt[1..].chars.all? { |c| 'neE'.include?(c) }

        opt[1..].each_char do |c|
          case c
          when 'n' then newline = false
          when 'e' then interpret_escapes = true
          when 'E' then interpret_escapes = false
          end
        end
        start_idx += 1
      end

      output = args[start_idx..].join(' ')

      # Process escape sequences if enabled
      if interpret_escapes
        output = process_echo_escapes(output)
        # Check for \c which stops output
        if output.include?(ECHO_STOP_OUTPUT)
          output = output.split(ECHO_STOP_OUTPUT).first || ''
          newline = false
        end
      end

      if newline
        puts output
      else
        print output
      end

      true
    end

    # Process escape sequences for echo (slightly different from printf)
    def process_echo_escapes(str)
      result = +''
      i = 0
      while i < str.length
        if str[i] == '\\' && i + 1 < str.length
          case str[i + 1]
          when 'n' then result << "\n"; i += 2
          when 't' then result << "\t"; i += 2
          when 'r' then result << "\r"; i += 2
          when 'a' then result << "\a"; i += 2
          when 'b' then result << "\b"; i += 2
          when 'f' then result << "\f"; i += 2
          when 'v' then result << "\v"; i += 2
          when '\\' then result << '\\'; i += 2
          when 'e', 'E' then result << "\e"; i += 2  # escape character
          when 'c'
            # \c stops output (no further characters printed, no newline)
            result << ECHO_STOP_OUTPUT
            break
          when '0'
            # Octal escape \0nnn (up to 3 octal digits)
            i += 2
            octal = +''
            while octal.length < 3 && i < str.length && str[i] >= '0' && str[i] <= '7'
              octal << str[i]
              i += 1
            end
            result << (octal.empty? ? "\0" : octal.to_i(8).chr)
          when 'x'
            # Hex escape \xHH (1 or 2 hex digits)
            i += 2
            hex = +''
            while hex.length < 2 && i < str.length && str[i] =~ /[0-9a-fA-F]/
              hex << str[i]
              i += 1
            end
            result << (hex.empty? ? '\\x' : hex.to_i(16).chr)
          else
            # Unknown escape, keep as-is
            result << str[i]
            i += 1
          end
        else
          result << str[i]
          i += 1
        end
      end
      result
    end

    def printf(*args)
      # printf [-v var] format [arguments...]
      # Supports: %s, %d, %i, %f, %e, %g, %x, %X, %o, %c, %b, %q, %%
      # Also supports width, precision, and flags: %-10s, %05d, %.2f, etc.
      # Dynamic width/precision: %*s (width from arg), %.*s (precision from arg), %*.*s (both)
      # %(fmt)T: format time using strftime format (arg is epoch seconds, -1=now, -2=shell start)
      # -v var: assign output to shell variable var instead of printing

      # Handle single array argument (from shell command) vs multiple args (from Ruby code)
      args = args.first if args.length == 1 && args.first.is_a?(Array)
      var_name = nil

      # Parse -v option
      while args.first&.start_with?('-')
        break if args.first == '--'
        if args.first == '-v'
          args.shift
          var_name = args.shift
          unless var_name
            $stderr.puts 'printf: -v: option requires an argument'
            return false
          end
          # Validate variable name
          unless var_name =~ /\A[a-zA-Z_][a-zA-Z0-9_]*\z/
            $stderr.puts "printf: `#{var_name}': not a valid identifier"
            return false
          end
        else
          $stderr.puts "printf: #{args.first}: invalid option"
          return false
        end
      end

      # Consume -- if present
      args.shift if args.first == '--'

      if args.empty?
        $stderr.puts 'printf: usage: printf [-v var] format [arguments]'
        return false
      end

      format = args.first
      arguments = args[1..] || []
      arg_index = 0

      # Process escape sequences in format string
      format = process_escape_sequences(format)

      # Build output by processing format specifiers
      output = +''
      i = 0
      while i < format.length
        if format[i] == '%'
          if i + 1 < format.length && format[i + 1] == '%'
            # Literal %
            output << '%'
            i += 2
            next
          end

          # Parse format specifier
          spec_start = i
          i += 1

          # Check for %(strftime_format)T time format
          if i < format.length && format[i] == '('
            # Find the closing )T
            paren_start = i + 1
            paren_end = format.index(')T', i)
            if paren_end
              strftime_fmt = format[paren_start...paren_end]
              i = paren_end + 2  # Skip past )T

              # Get the time argument
              arg = if arg_index < arguments.length
                      arguments[arg_index]
                    else
                      '-1'  # Default to current time
                    end
              arg_index += 1

              # Convert argument to time
              time = case arg.to_s
                     when '-1', ''
                       Time.now
                     when '-2'
                       # Shell start time - use a class variable or fall back to current
                       @shell_start_time ||= Time.now
                     else
                       Time.at(arg.to_i)
                     end

              output << time.strftime(strftime_fmt)
              next
            end
          end

          # Parse flags
          flags = +''
          while i < format.length && '-+ #0'.include?(format[i])
            flags << format[i]
            i += 1
          end

          # Parse width (can be * for dynamic width from argument)
          width = +''
          if i < format.length && format[i] == '*'
            # Dynamic width from argument
            i += 1
            width_arg = if arg_index < arguments.length
                          arguments[arg_index]
                        else
                          '0'
                        end
            arg_index += 1
            width_val = width_arg.to_i
            # Negative width means left-align
            if width_val < 0
              flags << '-' unless flags.include?('-')
              width_val = width_val.abs
            end
            width = width_val.to_s
          else
            while i < format.length && format[i] =~ /\d/
              width << format[i]
              i += 1
            end
          end

          # Parse precision (can be * for dynamic precision from argument)
          precision = nil
          if i < format.length && format[i] == '.'
            i += 1
            if i < format.length && format[i] == '*'
              # Dynamic precision from argument
              i += 1
              prec_arg = if arg_index < arguments.length
                           arguments[arg_index]
                         else
                           '0'
                         end
              arg_index += 1
              prec_val = prec_arg.to_i
              # Negative precision is treated as if precision were omitted
              precision = prec_val >= 0 ? prec_val.to_s : nil
            else
              precision = +''
              while i < format.length && format[i] =~ /\d/
                precision << format[i]
                i += 1
              end
            end
          end

          # Parse conversion specifier
          if i < format.length
            specifier = format[i]
            i += 1

            # Get argument (reuse arguments if we run out)
            arg = if arg_index < arguments.length
                    arguments[arg_index]
                  else
                    specifier =~ /[diouxXeEfFgG]/ ? '0' : ''
                  end
            arg_index += 1

            # Format the argument
            output << format_arg(specifier, arg, flags, width, precision)
          end
        else
          output << format[i]
          i += 1
        end
      end

      if var_name
        # Assign to variable instead of printing
        ENV[var_name] = output
      else
        print output
      end
      true
    end

    def process_escape_sequences(str)
      result = +''
      i = 0
      while i < str.length
        if str[i] == '\\' && i + 1 < str.length
          next_char = str[i + 1]
          case next_char
          when 'n' then result << "\n"; i += 2
          when 't' then result << "\t"; i += 2
          when 'r' then result << "\r"; i += 2
          when 'a' then result << "\a"; i += 2
          when 'b' then result << "\b"; i += 2
          when 'f' then result << "\f"; i += 2
          when 'v' then result << "\v"; i += 2
          when 'e', 'E' then result << "\e"; i += 2
          when '\\' then result << '\\'; i += 2
          when "'" then result << "'"; i += 2
          when '"' then result << '"'; i += 2
          when '?'  then result << '?'; i += 2
          when 'x'
            # Hex escape \xNN
            hex = str[i + 2, 2]
            if hex =~ /\A[0-9a-fA-F]{1,2}\z/
              result << hex.to_i(16).chr
              i += 2 + hex.length
            else
              result << str[i]; i += 1
            end
          when 'u'
            # Unicode escape \uNNNN (4 hex digits)
            hex = str[i + 2, 4]
            if hex =~ /\A[0-9a-fA-F]{4}\z/
              result << [hex.to_i(16)].pack('U')
              i += 6
            else
              result << str[i]; i += 1
            end
          when 'U'
            # Unicode escape \UNNNNNNNN (8 hex digits)
            hex = str[i + 2, 8]
            if hex =~ /\A[0-9a-fA-F]{8}\z/
              result << [hex.to_i(16)].pack('U')
              i += 10
            else
              result << str[i]; i += 1
            end
          when 'c'
            # Control character \cX
            if i + 2 < str.length
              ctrl_char = str[i + 2]
              result << (ctrl_char.ord & 0x1f).chr
              i += 3
            else
              result << str[i]; i += 1
            end
          when /[0-7]/
            # Octal escape \NNN (1-3 digits)
            octal = str[i + 1, 3].match(/\A[0-7]{1,3}/)[0]
            result << octal.to_i(8).chr
            i += 1 + octal.length
          else
            # Unknown escape - keep backslash and character
            result << str[i, 2]; i += 2
          end
        else
          result << str[i]; i += 1
        end
      end
      result
    end

    def shell_quote(str)
      # Quote a string for safe reuse as shell input (like bash's printf %q)
      # Returns a string that, when parsed by the shell, yields the original string

      # Empty string needs explicit quoting
      return "''" if str.empty?

      # If string contains only safe characters, no quoting needed
      # Safe chars: alphanumeric, underscore, hyphen, dot, slash, colon, at, percent, plus, comma, equals
      if str.match?(/\A[a-zA-Z0-9_\-.\/:@%+=,]+\z/)
        return str
      end

      # Use $'...' syntax for strings with control characters
      if str.match?(/[\x00-\x1f\x7f]/)
        return "$'" + str.gsub(/[\x00-\x1f\x7f'\\]/) { |c|
          case c
          when "\n" then '\\n'
          when "\t" then '\\t'
          when "\r" then '\\r'
          when "\a" then '\\a'
          when "\b" then '\\b'
          when "\f" then '\\f'
          when "\v" then '\\v'
          when "\e" then '\\e'
          when "'" then "\\'"
          when '\\' then '\\\\'
          else
            # Other control characters as octal
            format('\\%03o', c.ord)
          end
        } + "'"
      end

      # For strings with single quotes, use $'...' syntax
      if str.include?("'")
        return "$'" + str.gsub(/['\\]/) { |c|
          c == "'" ? "\\'" : '\\\\'
        } + "'"
      end

      # For other special characters, use single quotes
      # (single quotes preserve everything literally except single quote itself)
      "'" + str + "'"
    end

    def format_arg(specifier, arg, flags, width, precision)
      width_int = width.empty? ? nil : width.to_i
      prec_int = precision.nil? ? nil : (precision.empty? ? 0 : precision.to_i)

      result = case specifier
               when 's'
                 # String
                 s = arg.to_s
                 s = s[0, prec_int] if prec_int
                 s
               when 'd', 'i'
                 # Signed integer
                 num = arg.to_i
                 if prec_int
                   format("%0#{prec_int}d", num)
                 else
                   num.to_s
                 end
               when 'u'
                 # Unsigned integer
                 num = arg.to_i
                 num = num & 0xFFFFFFFF if num < 0
                 num.to_s
               when 'o'
                 # Octal
                 num = arg.to_i
                 prefix = flags.include?('#') ? '0' : ''
                 "#{prefix}#{num.to_s(8)}"
               when 'x'
                 # Hexadecimal lowercase
                 num = arg.to_i
                 prefix = flags.include?('#') ? '0x' : ''
                 "#{prefix}#{num.to_s(16)}"
               when 'X'
                 # Hexadecimal uppercase
                 num = arg.to_i
                 prefix = flags.include?('#') ? '0X' : ''
                 "#{prefix}#{num.to_s(16).upcase}"
               when 'f', 'F'
                 # Floating point
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}f", num)
               when 'e'
                 # Scientific notation lowercase
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}e", num)
               when 'E'
                 # Scientific notation uppercase
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}E", num)
               when 'g'
                 # Shorter of %e or %f
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}g", num)
               when 'G'
                 # Shorter of %E or %F
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}G", num)
               when 'c'
                 # Character
                 arg.to_s[0] || ''
               when 'b'
                 # String with backslash escapes
                 process_escape_sequences(arg.to_s)
               when 'q'
                 # Shell-quoted string (safe for reuse as shell input)
                 shell_quote(arg.to_s)
               else
                 arg.to_s
               end

      # Apply width and alignment
      if width_int
        if flags.include?('-')
          # Left-justify
          result = result.ljust(width_int)
        elsif flags.include?('0') && specifier =~ /[diouxXeEfFgG]/
          # Zero-pad numbers
          if result[0] == '-'
            result = "-#{result[1..].rjust(width_int - 1, '0')}"
          else
            result = result.rjust(width_int, '0')
          end
        else
          # Right-justify with spaces
          result = result.rjust(width_int)
        end
      end

      # Handle + flag for numbers
      if flags.include?('+') && specifier =~ /[dieEfFgG]/ && !result.start_with?('-')
        result = "+#{result}"
      elsif flags.include?(' ') && specifier =~ /[dieEfFgG]/ && !result.start_with?('-')
        result = " #{result}"
      end

      result
    end
  end
end
