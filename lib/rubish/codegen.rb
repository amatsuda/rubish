# frozen_string_literal: true

module Rubish
  class Codegen
    def generate(node)
      case node
      when AST::Command
        generate_command(node)
      when AST::Pipeline
        generate_pipeline(node)
      when AST::Negation
        generate_negation(node)
      when AST::List
        generate_list(node)
      when AST::Redirect
        generate_redirect(node)
      when AST::VarnameRedirect
        generate_varname_redirect(node)
      when AST::Background
        generate_background(node)
      when AST::And
        generate_and(node)
      when AST::Or
        generate_or(node)
      when AST::If
        generate_if(node)
      when AST::Unless
        generate_unless(node)
      when AST::While
        generate_while(node)
      when AST::Until
        generate_until(node)
      when AST::For
        generate_for(node)
      when AST::ArithFor
        generate_arith_for(node)
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
      when AST::ArithmeticCommand
        generate_arithmetic_command(node)
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

      # Generate prefix environment variables hash
      env_code = if node.env.empty?
                   nil
                 else
                   pairs = node.env.map do |assignment|
                     var, val = assignment.split('=', 2)
                     val ||= ''
                     "#{var.inspect} => #{generate_string_arg(val)}"
                   end
                   "{#{pairs.join(', ')}}"
                 end

      cmd = if args.empty? && env_code.nil?
              "__cmd(#{name})"
            elsif args.empty?
              "__cmd(#{name}, __prefix_env: #{env_code})"
            elsif env_code.nil?
              # Flatten args in case of glob expansion
              "__cmd(#{name}, *[#{args}].flatten)"
            else
              "__cmd(#{name}, *[#{args}].flatten, __prefix_env: #{env_code})"
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
        # Special case: $@ or "$@" as standalone arg should expand to array
        # so it becomes nothing when empty (not an empty string argument)
        if arg == '$@' || arg == '"$@"'
          return '@positional_params'
        end
        # Special case: $varname or "$varname" as standalone arg
        # Check if it's an array and expand accordingly
        if arg =~ /\A\$([a-zA-Z_][a-zA-Z0-9_]*)\z/ || arg =~ /\A"\$([a-zA-Z_][a-zA-Z0-9_]*)"\z/
          var_name = $1
          return "__fetch_var_for_arg(#{var_name.inspect})"
        end
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
      # $'...' ANSI-C quoting: process escape sequences
      if str.start_with?("$'") && str.end_with?("'")
        return "Builtins.process_escape_sequences(#{str[2...-1].inspect})"
      end

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
      # $'...' ANSI-C quoting: process escape sequences
      if str.start_with?("$'") && str.end_with?("'")
        return "Builtins.process_escape_sequences(#{str[2...-1].inspect})"
      end

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
          # Escape backslash for Ruby string
          result << '\\\\'
          i += 1
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
          # Quote removal: skip double quotes (they're used for grouping, not literal)
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
      # Check if last command is 'each' or 'map' with a block - handle specially
      # Also check for redirects wrapping each/map
      last_cmd = node.commands.last
      unwrapped_last = unwrap_redirect(last_cmd)

      if unwrapped_last.is_a?(AST::Command) && unwrapped_last.name == 'each' && unwrapped_last.block
        return generate_pipeline_with_each(node)
      elsif unwrapped_last.is_a?(AST::Command) && unwrapped_last.name == 'map' && unwrapped_last.block
        # map is just each with implicit echo - transform the block body
        return generate_pipeline_with_each(node, implicit_echo: true)
      elsif unwrapped_last.is_a?(AST::Command) && unwrapped_last.name == 'select' && unwrapped_last.block
        # select filters lines where block condition is true
        return generate_pipeline_with_each(node, filter: true)
      end

      # Handle pipe_types for |& (pipe both stdout and stderr)
      parts = []
      node.commands.each_with_index do |cmd, idx|
        element = generate_pipeline_element(cmd)

        # Check if this is followed by |& (pipe_both)
        if node.pipe_types && idx < node.pipe_types.length && node.pipe_types[idx] == :pipe_both
          # |& means redirect stderr to stdout before piping
          parts << "#{element}.redirect_err_to_out"
        else
          parts << element
        end
      end
      parts.join(' | ')
    end

    def generate_pipeline_with_each(node, implicit_echo: false, filter: false)
      # Generate code for: cmd1 | cmd2 | ... | each {|var| body}
      # Also handles map (with implicit_echo: true) and select (with filter: true)
      # Extract the each/map/select command and the source pipeline
      last_node = node.commands.last
      redirect_info = extract_redirect_info(last_node)
      each_cmd = unwrap_redirect(last_node)
      source_commands = node.commands[0...-1]
      source_pipe_types = node.pipe_types ? node.pipe_types[0...-1] : nil

      # Generate source pipeline code
      source_code = if source_commands.length == 1
                      generate(source_commands.first)
                    else
                      source_pipeline = AST::Pipeline.new(commands: source_commands, pipe_types: source_pipe_types)
                      generate_pipeline(source_pipeline)
                    end

      # Parse the block to extract variable and body
      var_name, body = parse_each_block(each_cmd.block)

      # For map, wrap body in echo to implicitly output the result
      body = "echo #{body}" if implicit_echo

      # For select, wrap body in conditional to filter lines
      body = "if #{body}; then echo $#{var_name}; fi" if filter

      # Generate the each loop
      parts = []
      parts << '__loop_break = catch(:break_loop) do'
      parts << "__each_loop(#{var_name.inspect}, -> { #{source_code} }, #{body.inspect}) do |__line|"
      parts << '__loop_cont = catch(:continue_loop) do'
      parts << "ENV[#{var_name.inspect}] = __line"
      parts << "__eval_shell_code(#{body.inspect})"
      parts << 'nil; end'
      parts << 'throw(:continue_loop, __loop_cont - 1) if __loop_cont.is_a?(Integer) && __loop_cont > 1'
      parts << 'next if __loop_cont'
      parts << 'end'
      parts << 'nil; end'
      parts << 'throw(:break_loop, __loop_break - 1) if __loop_break.is_a?(Integer) && __loop_break > 1'
      each_code = parts.join("\n")

      # If there's a redirect, wrap in subshell
      if redirect_info
        operator, target = redirect_info
        target_code = generate_string_arg(target)
        redirect_method = case operator
                          when '>' then 'redirect_out'
                          when '>>' then 'redirect_append'
                          when '2>' then 'redirect_err'
                          else 'redirect_out'
                          end
        "__subshell { #{each_code} }.#{redirect_method}(#{target_code})"
      else
        each_code
      end
    end

    def parse_each_block(block)
      # Parse block to extract variable and body
      # Supports formats with explicit variable:
      #   {|x| body}      - curly brace format
      #   do |x| body end - do/end format
      # Or implicit variable (defaults to 'it', accessed as $it):
      #   { body }        - curly brace without variable
      #   do body end     - do/end without variable
      if block =~ /\A\{\s*\|(\w+)\|\s*(.*)\s*\}\z/m
        # Curly brace format with variable: {|x| body}
        [$1, $2.strip]
      elsif block =~ /\A\{\s*(.*)\s*\}\z/m
        # Curly brace format without variable: { body } - use implicit 'it'
        ['it', $1.strip]
      elsif block =~ /\Ado\s+\|(\w+)\|\s*(.*)\s+end\z/m
        # Do/end format with variable: do |x| body end
        [$1, $2.strip]
      elsif block =~ /\Ado\s+(.*)\s+end\z/m
        # Do/end format without variable: do body end - use implicit 'it'
        ['it', $1.strip]
      else
        ['it', block]
      end
    end

    def unwrap_redirect(node)
      # Unwrap Redirect nodes to get the underlying command
      if node.is_a?(AST::Redirect)
        node.command
      else
        node
      end
    end

    def extract_redirect_info(node)
      # Extract redirect info from a node (returns [operator, target] or nil)
      if node.is_a?(AST::Redirect)
        [node.operator, node.target]
      else
        nil
      end
    end

    def generate_negation(node)
      "__negate { #{generate(node.command)} }"
    end

    def generate_pipeline_element(node)
      # Compound commands need to be wrapped in __subshell to work in pipelines
      # because they don't return Command objects that implement the | operator
      if pipeline_compound_command?(node)
        "__subshell { #{generate(node)} }"
      elsif node.is_a?(AST::Redirect) && pipeline_compound_command?(node.command)
        # Redirect wrapping a compound command - wrap in subshell and apply redirect
        target = generate_string_arg(node.target)
        op_method = case node.operator
                    when '>' then 'redirect_out'
                    when '>|' then 'redirect_clobber'
                    when '>>' then 'redirect_append'
                    when '<' then 'redirect_in'
                    when '2>' then 'redirect_err'
                    else 'redirect_out'
                    end
        "__subshell { #{generate(node.command)} }.#{op_method}(#{target})"
      else
        generate(node)
      end
    end

    def pipeline_compound_command?(node)
      case node
      when AST::For, AST::ArithFor, AST::While, AST::Until, AST::Select,
           AST::If, AST::Unless, AST::Case, AST::Function
        true
      else
        false
      end
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
                  when '>&' then 'dup_out'
                  when '<&' then 'dup_in'
                  end
      target = generate_string_arg(node.target)

      # For compound commands (loops, conditionals, etc.), use block-based redirection
      if compound_command?(node.command)
        "__with_redirect(#{node.operator.inspect}, #{target}) { #{generate(node.command)} }"
      else
        "#{generate(node.command)}.#{op_method}(#{target})"
      end
    end

    def compound_command?(node)
      # Compound commands that execute inline and can use __with_redirect
      # Subshell is excluded because it creates a Subshell object that is run later
      # and needs the redirect set on the object itself
      case node
      when AST::For, AST::ArithFor, AST::While, AST::Until, AST::Select,
           AST::If, AST::Unless, AST::Case, AST::Function
        true
      else
        false
      end
    end

    def generate_varname_redirect(node)
      # Generate code to allocate FD and redirect
      varname = node.varname.inspect
      operator = node.operator.inspect
      target = generate_string_arg(node.target)
      "__varname_redirect(#{varname}, #{operator}, #{target}) { #{generate(node.command)} }"
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
        # Use generate_loop_body to wrap single commands in __run_cmd
        # This ensures commands are executed immediately within the if block
        parts << generate_loop_body(body)
      end

      if node.else_body
        parts << 'else'
        parts << generate_loop_body(node.else_body)
      end

      parts << 'end'
      parts.join("\n")
    end

    def generate_unless(node)
      parts = []

      parts << "unless __condition { #{generate(node.condition)} }"
      parts << generate_loop_body(node.body)

      if node.else_body
        parts << 'else'
        parts << generate_loop_body(node.else_body)
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

    def generate_arith_for(node)
      # C-style for loop: for ((init; cond; update)); do body; done
      parts = []
      parts << '__loop_break = catch(:break_loop) do'
      parts << "__arith_for_loop(#{node.init.inspect}, #{node.condition.inspect}, #{node.update.inspect}) do"
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
      # Special handling for prompt functions with raw Ruby code
      if node.body.is_a?(AST::RubyCode)
        return "__define_function(#{node.name.inspect}, #{node.body.code.inspect}, nil) { nil }"
      end

      # Generate a function definition that stores a lambda
      body_code = generate_loop_body(node.body)
      # Also store shell source for declare -f
      source_code = to_shell(node.body)
      # Pass params array for Ruby-style def with arguments
      params_code = node.params ? node.params.inspect : 'nil'
      "__define_function(#{node.name.inspect}, #{source_code.inspect}, #{params_code}) { #{body_code} }"
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

    def generate_arithmetic_command(node)
      # Generate code for arithmetic command (( expression ))
      # The expression needs variable expansion but is evaluated as arithmetic
      "__arithmetic_command(#{node.expression.inspect})"
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

      # Handle ${var@operator} - transformation operators (Q, E, P, A, a, U, u, L, K)
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)@([QEPAaUuLK])\z/
        var_name = $1
        operator = $2
        return "__param_transform(#{var_name.inspect}, #{operator.inspect})"
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
      when AST::Unless
        parts = ["unless #{to_shell(node.condition)}"]
        parts << "    #{to_shell(node.body, indent + 1)}"
        if node.else_body
          parts << 'else'
          parts << "    #{to_shell(node.else_body, indent + 1)}"
        end
        parts << 'end'
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
