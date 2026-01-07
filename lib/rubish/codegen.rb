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
      when AST::Until
        generate_until(node)
      when AST::For
        generate_for(node)
      when AST::Select
        generate_select(node)
      when AST::Function
        generate_function(node)
      when AST::Case
        generate_case(node)
      when AST::Subshell
        generate_subshell(node)
      when AST::Heredoc
        generate_heredoc(node)
      when AST::Herestring
        generate_herestring(node)
      when AST::Coproc
        generate_coproc(node)
      when AST::Time
        generate_time(node)
      when AST::ConditionalExpr
        generate_conditional_expr(node)
      when AST::ArrayAssign
        generate_array_assign(node)
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
      when AST::ProcessSubstitution
        generate_process_substitution(arg)
      else
        arg.inspect
      end
    end

    def generate_process_substitution(node)
      direction = node.direction == :in ? ':in' : ':out'
      "__proc_sub(#{node.command.inspect}, #{direction})"
    end

    def has_glob_chars?(str)
      # Check for unquoted glob characters: *, ?, [...]
      str.match?(/[*?\[]/)
    end

    def has_brace_expansion?(str)
      # Check for brace expansion patterns: {a,b} or {1..5}
      # Must have matching braces with either comma or ..
      # But NOT ${...} which is parameter expansion
      return false unless str.include?('{') && str.include?('}')

      # Check for brace expansion, but exclude ${...} parameter expansion
      # ${var,} or ${var,,} are case modification, not brace expansion
      str.match?(/(?<!\$)\{[^}]*(?:,|\.\.)[^}]*\}/)
    end

    def generate_string_arg_with_glob(str)
      # Single-quoted strings: no expansion at all
      if str.start_with?("'") && str.end_with?("'")
        return str[1...-1].inspect
      end

      # Double-quoted strings: variable expansion but no glob/brace
      if str.start_with?('"') && str.end_with?('"')
        inner = str[1...-1]
        return generate_interpolated_string(inner)
      end

      # Check for brace expansion (happens before glob)
      if has_brace_expansion?(str)
        # Brace expansion returns an array, each element may need glob expansion
        if has_glob_chars?(str)
          # Both brace and glob: expand braces, then glob each result
          return "__brace(#{str.inspect}).flat_map { |x| __glob(x) }"
        else
          return "__brace(#{str.inspect})"
        end
      end

      # Check for glob characters (no brace)
      if has_glob_chars?(str)
        # If it also has variables, expand variables first then glob
        if str.include?('$')
          return "__glob(#{generate_interpolated_string(str)})"
        else
          return "__glob(#{str.inspect})"
        end
      end

      # No glob or brace chars - use normal string arg generation
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
        return "__fetch_var(#{$1.inspect})"
      end

      # Check if string contains any variables or backtick substitution
      if str.include?('$') || str.include?('`')
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
        '((a0 = ENV["RUBISH_ARGV0"]) && !a0.empty? ? a0 : @script_name)'
      when /\A\$([1-9])\z/
        "(@positional_params[#{$1.to_i - 1}] || '')"
      when '$#'
        '@positional_params.length.to_s'
      when '$@'
        '@positional_params.join(" ")'
      when '$*'
        'Builtins.join_by_ifs(@positional_params)'
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
        elsif char == '`'
          # Backtick command substitution
          cmd_expr, consumed = parse_backtick_substitution(str, i)
          if cmd_expr
            result << '#{' << cmd_expr << '}'
            i += consumed
          else
            result << '`'
            i += 1
          end
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
          return ["__run_subst(#{cmd.inspect})", j - pos]
        end
        return nil  # Unclosed, treat as literal
      end

      # Check for $"..." locale translation string
      if str[pos + 1] == '"'
        j = pos + 2
        content = +''  # Mutable string
        while j < str.length && str[j] != '"'
          if str[j] == '\\'
            # Handle escape sequences
            content << str[j, 2]
            j += 2
          else
            content << str[j]
            j += 1
          end
        end
        if j < str.length && str[j] == '"'
          # Process any variable expansions in the content first
          if content.include?('$')
            expanded = generate_interpolated_string(content)
            return ["__translate(#{expanded})", j - pos + 1]
          else
            return ["__translate(#{content.inspect})", j - pos + 1]
          end
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
        return ['((a0 = ENV["RUBISH_ARGV0"]) && !a0.empty? ? a0 : @script_name)', 2]
      when '$#'
        return ['@positional_params.length.to_s', 2]
      when '$@'
        return ['@positional_params.join(" ")', 2]
      when '$*'
        return ['Builtins.join_by_ifs(@positional_params)', 2]
      when /\$[1-9]/
        n = str[pos + 1].to_i
        return ["(@positional_params[#{n - 1}] || '')", 2]
      end

      # ${VAR} or ${VAR:operation} form
      if str[pos + 1] == '{'
        end_brace = find_matching_brace(str, pos + 1)
        if end_brace
          content = str[pos + 2...end_brace]
          expr = parse_parameter_expansion(content)
          return [expr, end_brace - pos + 1]
        end
      end

      # $VAR form
      if str[pos + 1] =~ /[a-zA-Z_]/
        j = pos + 1
        j += 1 while j < str.length && str[j] =~ /[a-zA-Z0-9_]/
        var_name = str[pos + 1...j]
        return ["__fetch_var(#{var_name.inspect})", j - pos]
      end

      nil
    end

    def parse_backtick_substitution(str, pos)
      return nil unless str[pos] == '`'

      # Find matching closing backtick
      j = pos + 1
      while j < str.length
        if str[j] == '\\'
          # Skip escaped character
          j += 2
        elsif str[j] == '`'
          # Found closing backtick
          cmd = str[pos + 1...j]
          return ["__run_subst(#{cmd.inspect})", j - pos + 1]
        else
          j += 1
        end
      end

      nil  # Unclosed backtick
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
                  when '>|' then 'redirect_clobber'
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
      parts << '__loop_break = catch(:break_loop) do'
      parts << "while __condition { #{generate(node.condition)} }"
      parts << '__loop_cont = catch(:continue_loop) do'
      parts << generate_loop_body(node.body)
      parts << 'nil; end'
      parts << 'throw(:continue_loop, __loop_cont - 1) if __loop_cont.is_a?(Integer) && __loop_cont > 1'
      parts << 'next if __loop_cont'
      parts << 'end'
      parts << 'nil; end'
      parts << 'throw(:break_loop, __loop_break - 1) if __loop_break.is_a?(Integer) && __loop_break > 1'
      parts.join("\n")
    end

    def generate_until(node)
      parts = []
      parts << '__loop_break = catch(:break_loop) do'
      parts << "until __condition { #{generate(node.condition)} }"
      parts << '__loop_cont = catch(:continue_loop) do'
      parts << generate_loop_body(node.body)
      parts << 'nil; end'
      parts << 'throw(:continue_loop, __loop_cont - 1) if __loop_cont.is_a?(Integer) && __loop_cont > 1'
      parts << 'next if __loop_cont'
      parts << 'end'
      parts << 'nil; end'
      parts << 'throw(:break_loop, __loop_break - 1) if __loop_break.is_a?(Integer) && __loop_break > 1'
      parts.join("\n")
    end

    def generate_for(node)
      items = node.items.map { |i| generate_for_item(i) }.join(', ')
      parts = []
      parts << '__loop_break = catch(:break_loop) do'
      parts << "__for_loop(#{escape_string(node.variable)}, [#{items}].flatten) do"
      parts << '__loop_cont = catch(:continue_loop) do'
      parts << generate_loop_body(node.body)
      parts << 'nil; end'
      parts << 'throw(:continue_loop, __loop_cont - 1) if __loop_cont.is_a?(Integer) && __loop_cont > 1'
      parts << 'next if __loop_cont'
      parts << 'end'
      parts << 'nil; end'
      parts << 'throw(:break_loop, __loop_break - 1) if __loop_break.is_a?(Integer) && __loop_break > 1'
      parts.join("\n")
    end

    def generate_for_item(item)
      # For loop items need word splitting on variable expansion
      # $VAR with value "a b c" should become three items
      # Also need glob/brace expansion for patterns like *.txt or {1..5}
      if item =~ /\A\$([a-zA-Z_][a-zA-Z0-9_]*)\z/
        # Simple variable - expand and split
        "ENV.fetch(#{$1.inspect}, '').split"
      elsif item =~ /\A\$\{([^}]+)\}\z/
        # Braced variable - expand and split
        "ENV.fetch(#{$1.inspect}, '').split"
      elsif item.include?('$')
        # Mixed content with variable - expand as string, then split
        "#{generate_interpolated_string(item)}.split"
      elsif has_brace_expansion?(item)
        # Brace expansion - may also have glob
        if has_glob_chars?(item)
          "__brace(#{item.inspect}).flat_map { |x| __glob(x) }"
        else
          "__brace(#{item.inspect})"
        end
      elsif has_glob_chars?(item)
        # Glob pattern - expand
        "__glob(#{item.inspect})"
      else
        # Literal - no splitting needed
        item.inspect
      end
    end

    def generate_select(node)
      items = node.items.map { |i| generate_for_item(i) }.join(', ')
      parts = []
      parts << '__loop_break = catch(:break_loop) do'
      parts << "__select_loop(#{escape_string(node.variable)}, [#{items}].flatten) do"
      parts << '__loop_cont = catch(:continue_loop) do'
      parts << generate_loop_body(node.body)
      parts << 'nil; end'
      parts << 'throw(:continue_loop, __loop_cont - 1) if __loop_cont.is_a?(Integer) && __loop_cont > 1'
      parts << 'next if __loop_cont'
      parts << 'end'
      parts << 'nil; end'
      parts << 'throw(:break_loop, __loop_break - 1) if __loop_break.is_a?(Integer) && __loop_break > 1'
      parts.join("\n")
    end

    def generate_loop_body(body)
      # Lists already wrap each command in __run_cmd, but single commands don't
      if body.is_a?(AST::List)
        generate(body)
      else
        "__run_cmd { #{generate(body)} }"
      end
    end

    def generate_function(node)
      # Generate a function definition that stores a lambda
      body_code = generate_loop_body(node.body)
      # Also store shell source for declare -f
      source_code = to_shell(node.body)
      "__define_function(#{node.name.inspect}, #{source_code.inspect}) { #{body_code} }"
    end

    def generate_case(node)
      parts = []
      word_expr = generate_string_arg(node.word)
      parts << "__case_word = #{word_expr}"

      node.branches.each_with_index do |(patterns, body), i|
        keyword = i == 0 ? 'if' : 'elsif'
        # Build condition: check if any pattern matches
        conditions = patterns.map { |p| generate_case_pattern_match(p) }
        parts << "#{keyword} #{conditions.join(' || ')}"
        parts << generate_loop_body(body)
      end

      parts << 'end'
      parts.join("\n")
    end

    def generate_case_pattern_match(pattern)
      # Convert shell pattern to fnmatch check
      # Handle variable expansion in patterns
      if pattern.include?('$')
        pattern_expr = generate_interpolated_string(pattern)
        "__case_match(#{pattern_expr}, __case_word)"
      else
        "__case_match(#{pattern.inspect}, __case_word)"
      end
    end

    def generate_subshell(node)
      body_code = generate_loop_body(node.body)
      "__subshell { #{body_code} }"
    end

    def generate_heredoc(node)
      cmd_code = generate(node.command)
      # Content is set by REPL/source before execution
      # At codegen time, we generate a call to __heredoc with placeholder
      "__heredoc(#{node.delimiter.inspect}, #{node.expand}, #{node.strip_tabs}) { #{cmd_code} }"
    end

    def generate_herestring(node)
      cmd_code = generate(node.command)
      string_expr = generate_string_arg(node.string)
      "__herestring(#{string_expr}) { #{cmd_code} }"
    end

    def generate_coproc(node)
      cmd_code = generate(node.command)
      "__coproc(#{node.name.inspect}) { #{cmd_code} }"
    end

    def generate_time(node)
      if node.command
        cmd_code = generate(node.command)
        "__time(#{node.posix_format}) { #{cmd_code} }"
      else
        # time with no command just prints timing info (zeros)
        "__time(#{node.posix_format}) { nil }"
      end
    end

    def generate_conditional_expr(node)
      # Convert tokens to expression parts for runtime evaluation
      parts = node.expression.map do |token|
        case token.type
        when :WORD
          generate_string_arg(token.value)
        when :AND
          '"&&"'
        when :OR
          '"||"'
        when :LPAREN
          '"("'
        when :RPAREN
          '")"'
        else
          token.value.inspect
        end
      end
      "__cond_test([#{parts.join(', ')}])"
    end

    def generate_array_assign(node)
      # Generate code for array assignment: VAR=(a b c) or VAR+=(d e)
      var_part = node.var
      elements = node.elements

      # Generate element expressions
      elem_code = elements.map { |e| generate_string_arg(e) }.join(', ')

      # Call runtime method to handle the assignment
      "__array_assign(#{var_part.inspect}, [#{elem_code}])"
    end

    def escape_string(str)
      str.inspect
    end

    def find_matching_brace(str, open_pos)
      # Find matching } for { at open_pos, handling nested braces
      depth = 1
      i = open_pos + 1
      while i < str.length && depth > 0
        case str[i]
        when '{'
          depth += 1
        when '}'
          depth -= 1
        when '\\'
          i += 1  # Skip escaped character
        end
        i += 1
      end
      depth == 0 ? i - 1 : nil
    end

    def parse_parameter_expansion(content)
      # Handle ${!arr[@]} or ${!arr[*]} - array keys/indices
      if content =~ /\A!([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\z/
        var_name = $1
        return "__array_keys(#{var_name.inspect})"
      end

      # Handle ${#arr[@]} or ${#arr[*]} - array length
      if content =~ /\A#([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\z/
        var_name = $1
        return "__array_length(#{var_name.inspect})"
      end

      # Handle ${arr[@]} or ${arr[*]} - all array elements
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([@*])\]\z/
        var_name = $1
        mode = $2
        return "__array_all(#{var_name.inspect}, #{mode.inspect})"
      end

      # Handle ${arr[n]} - array element access
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\]\z/
        var_name = $1
        index = $2
        return "__array_element(#{var_name.inspect}, #{index.inspect})"
      end

      # Handle ${!var} - indirect expansion
      if content =~ /\A!([a-zA-Z_][a-zA-Z0-9_]*)\z/
        var_name = $1
        return "__param_indirect(#{var_name.inspect})"
      end

      # Handle ${#var} - length
      if content =~ /\A#([a-zA-Z_][a-zA-Z0-9_]*)\z/
        var_name = $1
        return "__param_length(#{var_name.inspect})"
      end

      # Handle ${var:offset} and ${var:offset:length} - must check before other : operators
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*):(-?\d+)(?::(-?\d+))?\z/
        var_name = $1
        offset = $2
        length = $3
        if length
          return "__param_substring(#{var_name.inspect}, #{offset}, #{length})"
        else
          return "__param_substring(#{var_name.inspect}, #{offset}, nil)"
        end
      end

      # Handle ${var//pattern/replacement} and ${var/pattern/replacement}
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)(\/\/|\/)((?:[^\/]|\\.)*)\/((?:[^\/]|\\.)*)?\z/
        var_name = $1
        operator = $2
        pattern = $3
        replacement = $4 || ''
        return "__param_replace(#{var_name.inspect}, #{operator.inspect}, #{pattern.inspect}, #{replacement.inspect})"
      end

      # Handle ${var/pattern} - delete first match (no replacement)
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)(\/\/|\/)((?:[^\/]|\\.)+)\z/
        var_name = $1
        operator = $2
        pattern = $3
        return "__param_replace(#{var_name.inspect}, #{operator.inspect}, #{pattern.inspect}, '')"
      end

      # Handle ${var^^}, ${var^}, ${var,,}, ${var,} - case modification
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)(\^\^|\^|,,|,)(?:([^}]*))?\z/
        var_name = $1
        operator = $2
        pattern = $3 || ''
        return "__param_case(#{var_name.inspect}, #{operator.inspect}, #{pattern.inspect})"
      end

      # Handle ${var##pattern} and ${var%%pattern} - greedy versions first
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)(##|%%)(.+)\z/
        var_name = $1
        operator = $2
        operand = $3
        return "__param_expand(#{var_name.inspect}, #{operator.inspect}, #{operand.inspect})"
      end

      # Handle ${var#pattern} and ${var%pattern} - non-greedy versions
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)(#|%)(.+)\z/
        var_name = $1
        operator = $2
        operand = $3
        return "__param_expand(#{var_name.inspect}, #{operator.inspect}, #{operand.inspect})"
      end

      # Handle ${var:-default}, ${var:=default}, ${var:+value}, ${var:?message}
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)(:-|:=|:\+|:\?)(.*)?\z/
        var_name = $1
        operator = $2
        operand = $3 || ''
        return "__param_expand(#{var_name.inspect}, #{operator.inspect}, #{operand.inspect})"
      end

      # Handle ${var-default}, ${var=default}, ${var+value}, ${var?message} (unset only, not null)
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)(-|=|\+|\?)(.*)?\z/
        var_name = $1
        operator = $2
        operand = $3 || ''
        return "__param_expand(#{var_name.inspect}, #{operator.inspect}, #{operand.inspect})"
      end

      # Simple ${VAR}
      "__fetch_var(#{content.inspect})"
    end

    # Convert AST back to shell source (for declare -f)
    def to_shell(node, indent = 0)
      prefix = '    ' * indent
      case node
      when AST::Command
        parts = [node.name] + node.args
        parts.join(' ')
      when AST::Pipeline
        node.commands.map { |c| to_shell(c) }.join(' | ')
      when AST::List
        node.commands.map { |c| to_shell(c, indent) }.join('; ')
      when AST::Redirect
        cmd = to_shell(node.command)
        "#{cmd} #{node.operator} #{node.target}"
      when AST::Background
        "#{to_shell(node.command)} &"
      when AST::And
        "#{to_shell(node.left)} && #{to_shell(node.right)}"
      when AST::Or
        "#{to_shell(node.left)} || #{to_shell(node.right)}"
      when AST::If
        parts = []
        node.branches.each_with_index do |(cond, body), i|
          keyword = i == 0 ? 'if' : 'elif'
          parts << "#{keyword} #{to_shell(cond)}; then"
          parts << "    #{to_shell(body, indent + 1)}"
        end
        if node.else_body
          parts << 'else'
          parts << "    #{to_shell(node.else_body, indent + 1)}"
        end
        parts << 'fi'
        parts.join("\n#{prefix}")
      when AST::While
        "while #{to_shell(node.condition)}; do\n#{prefix}    #{to_shell(node.body, indent + 1)}\n#{prefix}done"
      when AST::Until
        "until #{to_shell(node.condition)}; do\n#{prefix}    #{to_shell(node.body, indent + 1)}\n#{prefix}done"
      when AST::For
        items = node.items ? " in #{node.items.join(' ')}" : ''
        "for #{node.variable}#{items}; do\n#{prefix}    #{to_shell(node.body, indent + 1)}\n#{prefix}done"
      when AST::Case
        parts = ["case #{node.word} in"]
        node.branches.each do |(patterns, body)|
          parts << "    #{patterns.join('|')}) #{to_shell(body)} ;;"
        end
        parts << 'esac'
        parts.join("\n#{prefix}")
      when AST::Subshell
        "(#{to_shell(node.body)})"
      when AST::Function
        "#{node.name}() {\n#{prefix}    #{to_shell(node.body, indent + 1)}\n#{prefix}}"
      when NilClass
        ''
      else
        node.to_s
      end
    end
  end
end
