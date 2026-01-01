# frozen_string_literal: true

module Rubish
  class Codegen
    def generate(node)
      case node
      when AST::Command
        generate_command(node)
      when AST::Pipeline
        generate_pipeline(node)
      when AST::List
        generate_list(node)
      when AST::Redirect
        generate_redirect(node)
      when AST::Background
        generate_background(node)
      when AST::And
        generate_and(node)
      when AST::Or
        generate_or(node)
      when AST::If
        generate_if(node)
      when AST::While
        generate_while(node)
      when AST::For
        generate_for(node)
      else
        raise "Unknown AST node: #{node.class}"
      end
    end

    private

    def generate_command(node)
      args = node.args.map { |a| generate_arg(a) }.join(', ')
      name = generate_string_arg(node.name)
      cmd = if args.empty?
              "__cmd(#{name})"
            else
              # Flatten args in case of glob expansion
              "__cmd(#{name}, *[#{args}].flatten)"
            end

      # Append block if present
      if node.block
        cmd = "#{cmd} #{node.block}"
      end

      cmd
    end

    def generate_arg(arg)
      case arg
      when String
        generate_string_arg_with_glob(arg)
      when AST::ArrayLiteral
        arg.value  # Already valid Ruby: [1, 2, 3]
      when AST::RegexpLiteral
        arg.value  # Already valid Ruby: /pattern/
      else
        arg.inspect
      end
    end

    def has_glob_chars?(str)
      # Check for unquoted glob characters: *, ?, [...]
      str.match?(/[*?\[]/)
    end

    def generate_string_arg_with_glob(str)
      # Single-quoted strings: no expansion at all
      if str.start_with?("'") && str.end_with?("'")
        return str[1...-1].inspect
      end

      # Double-quoted strings: variable expansion but no glob
      if str.start_with?('"') && str.end_with?('"')
        inner = str[1...-1]
        return generate_interpolated_string(inner)
      end

      # Unquoted: check for glob characters
      if has_glob_chars?(str)
        # If it also has variables, expand variables first then glob
        if str.include?('$')
          return "__glob(#{generate_interpolated_string(str)})"
        else
          return "__glob(#{str.inspect})"
        end
      end

      # No glob chars - use normal string arg generation
      generate_string_arg(str)
    end

    def generate_string_arg(str)
      # Single-quoted strings: no expansion, strip quotes
      if str.start_with?("'") && str.end_with?("'")
        return str[1...-1].inspect
      end

      # Double-quoted strings: strip quotes, expand variables
      if str.start_with?('"') && str.end_with?('"')
        inner = str[1...-1]
        return generate_interpolated_string(inner)
      end

      # Check for special variables as standalone first
      special = generate_special_variable(str)
      return special if special

      # Unquoted: expand variables
      # If it's just a simple variable (not special), return the expression directly
      if str =~ /\A\$([a-zA-Z_][a-zA-Z0-9_]*)\z/
        return "ENV.fetch(#{$1.inspect}, '')"
      end

      # Check if string contains any variables
      if str.include?('$')
        generate_interpolated_string(str)
      else
        str.inspect
      end
    end

    def generate_special_variable(str)
      case str
      when '$?'
        '@last_status.to_s'
      when '$$'
        'Process.pid.to_s'
      when '$!'
        '(@last_bg_pid ? @last_bg_pid.to_s : "")'
      when '$0'
        '@script_name'
      when /\A\$([1-9])\z/
        "(@positional_params[#{$1.to_i - 1}] || '')"
      when '$#'
        '@positional_params.length.to_s'
      when '$@', '$*'
        '@positional_params.join(" ")'
      else
        nil
      end
    end

    def generate_interpolated_string(str)
      # Build a Ruby string with interpolation for variables
      result = +'"'
      i = 0

      while i < str.length
        char = str[i]

        if char == '\\'
          # Escape sequence - keep as-is
          result << str[i, 2]
          i += 2
        elsif char == '$'
          # Variable expansion
          var_expr, consumed = parse_variable(str, i)
          if var_expr
            result << '#{' << var_expr << '}'
            i += consumed
          else
            result << '$'
            i += 1
          end
        elsif char == '"'
          # Escape double quotes in the output
          result << '\\"'
          i += 1
        else
          result << char
          i += 1
        end
      end

      result << '"'
      result
    end

    def parse_variable(str, pos)
      return nil unless str[pos] == '$'

      # Check for arithmetic expansion $((...))
      if str[pos + 1] == '(' && str[pos + 2] == '('
        depth = 2
        j = pos + 3
        while j < str.length && depth > 0
          if str[j] == '('
            depth += 1
          elsif str[j] == ')'
            depth -= 1
          end
          j += 1
        end
        if depth == 0
          expr = str[pos + 3...j - 2]
          return ["__arith(#{expr.inspect})", j - pos]
        end
        return nil  # Unclosed, treat as literal
      end

      # Check for command substitution $(...)
      if str[pos + 1] == '('
        depth = 1
        j = pos + 2
        while j < str.length && depth > 0
          if str[j] == '('
            depth += 1
          elsif str[j] == ')'
            depth -= 1
          end
          j += 1
        end
        if depth == 0
          cmd = str[pos + 2...j - 1]
          return ["`#{cmd}`.chomp", j - pos]
        end
        return nil  # Unclosed, treat as literal
      end

      # Check for special variables first
      two_char = str[pos, 2]
      case two_char
      when '$?'
        return ['@last_status.to_s', 2]
      when '$$'
        return ['Process.pid.to_s', 2]
      when '$!'
        return ['(@last_bg_pid ? @last_bg_pid.to_s : "")', 2]
      when '$0'
        return ['@script_name', 2]
      when '$#'
        return ['@positional_params.length.to_s', 2]
      when '$@', '$*'
        return ['@positional_params.join(" ")', 2]
      when /\$[1-9]/
        n = str[pos + 1].to_i
        return ["(@positional_params[#{n - 1}] || '')", 2]
      end

      # ${VAR} form
      if str[pos + 1] == '{'
        end_brace = str.index('}', pos + 2)
        if end_brace
          var_name = str[pos + 2...end_brace]
          return ["ENV.fetch(#{var_name.inspect}, '')", end_brace - pos + 1]
        end
      end

      # $VAR form
      if str[pos + 1] =~ /[a-zA-Z_]/
        j = pos + 1
        j += 1 while j < str.length && str[j] =~ /[a-zA-Z0-9_]/
        var_name = str[pos + 1...j]
        return ["ENV.fetch(#{var_name.inspect}, '')", j - pos]
      end

      nil
    end

    def generate_pipeline(node)
      node.commands.map { |c| generate(c) }.join(' | ')
    end

    def generate_list(node)
      # Each command in a list needs to run, not just the last one
      node.commands.map { |c| "__run_cmd { #{generate(c)} }" }.join('; ')
    end

    def generate_redirect(node)
      op_method = case node.operator
                  when '>' then 'redirect_out'
                  when '>>' then 'redirect_append'
                  when '<' then 'redirect_in'
                  when '2>' then 'redirect_err'
                  end
      target = generate_string_arg(node.target)
      "#{generate(node.command)}.#{op_method}(#{target})"
    end

    def generate_background(node)
      "__background { #{generate(node.command)} }"
    end

    def generate_and(node)
      "__and_cmd(-> { #{generate(node.left)} }, -> { #{generate(node.right)} })"
    end

    def generate_or(node)
      "__or_cmd(-> { #{generate(node.left)} }, -> { #{generate(node.right)} })"
    end

    def generate_if(node)
      parts = []

      node.branches.each_with_index do |(condition, body), i|
        keyword = i == 0 ? 'if' : 'elsif'
        parts << "#{keyword} __condition { #{generate(condition)} }"
        parts << generate(body)
      end

      if node.else_body
        parts << 'else'
        parts << generate(node.else_body)
      end

      parts << 'end'
      parts.join("\n")
    end

    def generate_while(node)
      parts = []
      parts << "while __condition { #{generate(node.condition)} }"
      parts << generate_loop_body(node.body)
      parts << 'end'
      parts.join("\n")
    end

    def generate_for(node)
      items = node.items.map { |i| generate_for_item(i) }.join(', ')
      parts = []
      parts << "__for_loop(#{escape_string(node.variable)}, [#{items}].flatten) do"
      parts << generate_loop_body(node.body)
      parts << 'end'
      parts.join("\n")
    end

    def generate_for_item(item)
      # For loop items need word splitting on variable expansion
      # $VAR with value "a b c" should become three items
      # Also need glob expansion for patterns like *.txt
      if item =~ /\A\$([a-zA-Z_][a-zA-Z0-9_]*)\z/
        # Simple variable - expand and split
        "ENV.fetch(#{$1.inspect}, '').split"
      elsif item =~ /\A\$\{([^}]+)\}\z/
        # Braced variable - expand and split
        "ENV.fetch(#{$1.inspect}, '').split"
      elsif item.include?('$')
        # Mixed content with variable - expand as string, then split
        "#{generate_interpolated_string(item)}.split"
      elsif has_glob_chars?(item)
        # Glob pattern - expand
        "__glob(#{item.inspect})"
      else
        # Literal - no splitting needed
        item.inspect
      end
    end

    def generate_loop_body(body)
      # Lists already wrap each command in __run_cmd, but single commands don't
      if body.is_a?(AST::List)
        generate(body)
      else
        "__run_cmd { #{generate(body)} }"
      end
    end

    def escape_string(str)
      str.inspect
    end
  end
end
