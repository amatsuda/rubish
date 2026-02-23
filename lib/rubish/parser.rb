# frozen_string_literal: true

module Rubish
  class Parser
    def initialize(tokens)
      @tokens = tokens
      @pos = 0
    end

    def parse
      return nil if @tokens.empty?

      parse_list
    end

    private

    def current
      @tokens[@pos]
    end

    def peek(type)
      current&.type == type
    end

    def peek_any(*types)
      types.include?(current&.type)
    end

    def peek_at(offset, type)
      @tokens[@pos + offset]&.type == type
    end

    def consume(type = nil)
      return nil if @pos >= @tokens.length
      return nil if type && current.type != type

      token = current
      @pos += 1
      token
    end

    # list : conditional ((';' | '&') conditional)*
    def parse_list
      first = parse_conditional
      return nil unless first

      commands = [first]
      while peek(:SEMICOLON) || peek(:AMPERSAND)
        op = consume
        if op.type == :AMPERSAND && !peek_any(:WORD, :ARRAY, :IF, :WHILE, :FOR)
          # Trailing &, make last command background
          commands[-1] = AST::Background.new(commands[-1])
          break
        end
        next_cmd = parse_conditional
        commands << next_cmd if next_cmd
      end

      commands.length == 1 ? commands.first : AST::List.new(commands)
    end

    # conditional : pipeline (('&&' | '||') pipeline)*
    def parse_conditional
      left = parse_pipeline
      return nil unless left

      while peek(:AND) || peek(:OR)
        op = consume
        right = parse_pipeline
        left = if op.type == :AND
                 AST::And.new(left, right)
               else
                 AST::Or.new(left, right)
               end
      end

      left
    end

    # pipeline : ['!'] [time [-p]] command (('|' | '|&') command)*
    def parse_pipeline
      # Check for ! negation prefix
      negated = false
      if peek(:WORD) && current.value == '!'
        consume(:WORD)
        negated = true
      end

      # Check for time prefix
      if peek(:TIME)
        result = parse_time
        return negated ? AST::Negation.new(result) : result
      end

      first = parse_command
      return nil unless first

      commands = [first]
      pipe_types = []
      while peek(:PIPE) || peek(:PIPE_BOTH) || peek(:DOT) ||
            (peek(:WORD) && current.value =~ /\A\.(each|map|select|detect)\z/ && peek_at(1, :BLOCK))
        if peek(:PIPE_BOTH)
          consume(:PIPE_BOTH)
          pipe_types << :pipe_both
        elsif peek(:WORD) && current.value =~ /\A\.(each|map|select|detect)\z/ && peek_at(1, :BLOCK)
          # .each/.map/.select/.detect {block} after FUNC_CALL - tokenized as single WORD
          method_name = consume(:WORD).value[1..]  # remove leading '.'
          block = consume(:BLOCK).value
          cmd = AST::Command.new(name: method_name, block: block)
          # Check for redirections after the block
          cmd = parse_redirections(cmd)
          commands << cmd
          pipe_types << :pipe
          next
        elsif peek(:DOT)
          # Method chain syntax: cmd.method(args) is equivalent to cmd | method args
          consume(:DOT)
          if peek(:FUNC_CALL)
            cmd = parse_func_call
            commands << cmd if cmd
            pipe_types << :pipe
          elsif (peek(:WORD) && current.value =~ /\A(each|map|detect)\z/ && peek_at(1, :BLOCK)) ||
                (peek(:SELECT) && peek_at(1, :BLOCK))
            # .each/.map/.select/.detect {|var| body } - treat as regular command with block in pipeline
            # Note: select is tokenized as :SELECT, not :WORD
            method_name = current.value
            consume  # consume WORD or SELECT
            block = consume(:BLOCK).value
            cmd = AST::Command.new(name: method_name, block: block)
            # Check for redirections after the block
            cmd = parse_redirections(cmd)
            commands << cmd
            pipe_types << :pipe
          else
            # Unexpected token after DOT, break
            break
          end
          next
        else
          consume(:PIPE)
          pipe_types << :pipe
        end
        # Check for select { block } - filtering select (not shell select loop)
        if peek(:SELECT) && peek_at(1, :BLOCK)
          consume(:SELECT)
          block = consume(:BLOCK).value
          cmd = AST::Command.new(name: 'select', block: block)
          cmd = parse_redirections(cmd)
          commands << cmd
          next
        end
        cmd = parse_command
        commands << cmd if cmd
      end

      result = if commands.length == 1
                 commands.first
               else
                 AST::Pipeline.new(commands: commands, pipe_types: pipe_types)
               end

      negated ? AST::Negation.new(result) : result
    end

    # time : TIME [-p] pipeline
    def parse_time
      consume(:TIME)

      # Check for -p flag (POSIX format)
      posix_format = false
      if peek(:WORD) && current.value == '-p'
        consume(:WORD)
        posix_format = true
      end

      # Parse the command/pipeline to time
      first = parse_command
      return AST::Time.new(command: nil, posix_format: posix_format) unless first

      commands = [first]
      pipe_types = []
      while peek(:PIPE) || peek(:PIPE_BOTH)
        if peek(:PIPE_BOTH)
          consume(:PIPE_BOTH)
          pipe_types << :pipe_both
        else
          consume(:PIPE)
          pipe_types << :pipe
        end
        cmd = parse_command
        commands << cmd if cmd
      end

      timed_cmd = if commands.length == 1
                    commands.first
                  else
                    AST::Pipeline.new(commands: commands, pipe_types: pipe_types)
                  end
      AST::Time.new(command: timed_cmd, posix_format: posix_format)
    end

    # command : if_statement | while_statement | until_statement | for_statement | case_statement | function_def | subshell | coproc | conditional_expr | array_assign | WORD arg* block? (redirection)*
    # arg : WORD | ARRAY
    def parse_command
      # Check for control structures (compound commands support redirections)
      compound_cmd = if peek(:IF)
                       parse_if
                     elsif peek(:UNLESS)
                       parse_unless
                     elsif peek(:WHILE)
                       parse_while
                     elsif peek(:UNTIL)
                       parse_until
                     elsif peek(:FOR)
                       parse_for
                     elsif peek(:SELECT)
                       parse_select
                     elsif peek(:CASE)
                       parse_case
                     elsif peek(:FUNCTION)
                       parse_function_keyword
                     elsif peek(:DEF)
                       parse_def
                     elsif peek(:LPAREN)
                       parse_subshell
                     elsif peek(:COPROC)
                       parse_coproc
                     elsif peek(:LAZY_LOAD)
                       parse_lazy_load
                     elsif peek(:DOUBLE_LBRACKET)
                       parse_conditional_expr
                     elsif peek(:ARITH_CMD)
                       parse_arithmetic_command
                     end

      if compound_cmd
        # Compound commands can have redirections too (e.g., for ... done > file)
        return parse_redirections(compound_cmd)
      end

      # Check for array assignment: VAR=(a b c) or VAR+=(d e)
      return parse_array_assign if peek(:ARRAY_ASSIGN)

      # Check for function call syntax: cmd(arg1, arg2)
      return parse_func_call if peek(:FUNC_CALL)

      return nil unless peek(:WORD)

      # Collect prefix environment variable assignments (e.g., FOO=bar BAZ=qux cmd)
      prefix_env = []
      while peek(:WORD) && assignment?(current.value)
        # Check if there's a command after this assignment
        # If the next token is also a WORD (and possibly an assignment), continue collecting
        # If there's no next WORD, this is a bare assignment, not a prefix env
        next_pos = @pos + 1
        next_token = @tokens[next_pos]
        if next_pos < @tokens.length && [:WORD, :ARRAY, :PROC_SUB_IN, :PROC_SUB_OUT].include?(next_token&.type)
          # Check if the next token is also an assignment - if it's followed by
          # nothing or by end-of-input, then ALL of these are bare assignments, not prefix env
          # This handles: A=1 B=2 C=3 (all assignments, no command)
          if next_token.type == :WORD && assignment?(next_token.value)
            # Look ahead to see if there's a real command after all the assignments
            look_pos = next_pos + 1
            found_command = false
            while look_pos < @tokens.length
              tok = @tokens[look_pos]
              if tok.type == :WORD && assignment?(tok.value)
                look_pos += 1
              elsif [:WORD, :ARRAY, :PROC_SUB_IN, :PROC_SUB_OUT].include?(tok.type)
                found_command = true
                break
              else
                break
              end
            end
            unless found_command
              # All remaining tokens are assignments, no command follows
              break
            end
          end
          prefix_env << consume(:WORD).value
        else
          # No command follows, let caller handle as bare assignment
          break
        end
      end

      return nil unless peek(:WORD)

      name = consume(:WORD).value

      # Check for function definition: name() { body }
      if peek(:PARENS)
        consume(:PARENS)
        return parse_function_body(name)
      end

      args = []

      # Parse arguments (WORD, ARRAY, REGEXP, PROC_SUB_IN, PROC_SUB_OUT)
      while peek_any(:WORD, :ARRAY, :PROC_SUB_IN, :PROC_SUB_OUT)
        args << parse_arg
      end

      cmd = AST::Command.new(name: name, args: args, env: prefix_env)
      parse_redirections(cmd)
    end

    # Check if a string looks like a variable assignment (VAR=value or VAR+=value)
    def assignment?(str)
      str.match?(/\A[A-Za-z_][A-Za-z0-9_]*\+?=/)
    end

    # function_def : FUNCTION WORD '{' body '}'
    def parse_function_keyword
      consume(:FUNCTION)
      name = consume(:WORD)&.value || raise('Expected function name after "function"')
      parse_function_body(name)
    end

    # Ruby-style function: def name ... end or def name(arg1, arg2) ... end
    def parse_def
      consume(:DEF)
      name = consume(:WORD)&.value || raise('Expected function name after "def"')
      params = parse_def_params
      skip_semicolon

      body = parse_def_body
      consume_word('end') || raise('Expected "end" to close def')
      AST::Function.new(name, body, params)
    end

    # Capture raw token values until 'end' keyword for Ruby code blocks
    # Preserves structure by not adding spaces between tokens that should be adjacent
    def capture_raw_until_end
      parts = []
      depth = 1
      prev_token = nil

      while current && depth > 0
        # Track nested def/if/while/etc for proper end matching
        if current.type == :DEF || current.type == :IF || current.type == :WHILE ||
           current.type == :UNTIL || current.type == :FOR || current.type == :CASE ||
           current.type == :UNLESS
          depth += 1
        elsif current.value == 'end'
          depth -= 1
          break if depth == 0
        end

        # Handle shell tokens that have different meaning in Ruby
        val = case current.type
              when :HEREDOC
                # << in Ruby is append operator, reconstruct it
                raw = current.value.to_s
                if raw.end_with?(':quoted')
                  delimiter = raw.sub(/:quoted$/, '')
                  "<< \"#{delimiter}\""
                else
                  "<< #{raw}"
                end
              when :HEREDOC_INDENT
                # <<- in Ruby is heredoc, reconstruct it
                raw = current.value.to_s
                if raw.end_with?(':quoted')
                  delimiter = raw.sub(/:quoted$/, '')
                  "<<- \"#{delimiter}\""
                else
                  "<<- #{raw}"
                end
              when :HERESTRING
                # <<< in shell, but unlikely in Ruby - preserve anyway
                "<<< #{current.value}"
              else
                current.value.to_s
              end

        # Determine if we need a space before this token
        need_space = !parts.empty? && prev_token &&
                     !prev_token.end_with?('(', '[', '{', '.', ':', "\n") &&
                     !val.start_with?(')', ']', '}', ',', '.', ':', ';', "\n") &&
                     !(prev_token =~ /\A\w+\z/ && val == '(')  # no space between name and (

        parts << ' ' if need_space
        parts << val
        prev_token = val
        consume
      end

      parts.join.strip
    end

    # Parse optional parameter list for def: (arg1, arg2, ...) or (*args)
    # Splat param (*name) captures all remaining arguments
    def parse_def_params
      # Allow empty ()
      if peek(:PARENS)
        consume(:PARENS)
        return []
      end

      # Check for ( with arguments
      return nil unless peek(:LPAREN)

      consume(:LPAREN)
      params = []

      until peek(:RPAREN)
        word = consume(:WORD)&.value
        break unless word

        # Handle comma-separated params (comma may be attached to word)
        if word.end_with?(',')
          params << word.chomp(',')
        else
          params << word
          break  # No comma means end of params
        end
      end

      consume(:RPAREN) || raise('Expected ")" to close parameter list')
      params
    end

    # Check if param is a splat (*args)
    def splat_param?(param)
      param.start_with?('*')
    end

    # Get the name from a splat param (*args -> args)
    def splat_param_name(param)
      param[1..]
    end

    # Parse body of def (stops at end)
    def parse_def_body
      commands = []
      skip_semicolon

      while !peek_end && current
        cmd = parse_conditional
        break unless cmd

        commands << cmd
        skip_semicolon
      end

      commands.length == 1 ? commands.first : AST::List.new(commands)
    end

    # Parse function body: { commands }
    def parse_function_body(name)
      consume(:LBRACE) || raise('Expected "{" for function body')
      body = parse_function_body_commands
      consume(:RBRACE) || raise('Expected "}" to close function body')
      AST::Function.new(name, body, nil)
    end

    # Parse commands inside function body (stops at })
    def parse_function_body_commands
      commands = []
      skip_semicolon

      while !peek(:RBRACE) && current
        cmd = parse_conditional
        break unless cmd

        commands << cmd
        skip_semicolon
      end

      commands.length == 1 ? commands.first : AST::List.new(commands)
    end

    # if_statement : IF conditional [THEN] body (ELIF conditional [THEN] body)* (ELSE body)? FI
    def parse_if
      consume(:IF)
      branches = []

      # Parse first branch
      condition = parse_conditional_for_if
      skip_semicolon
      # 'then' is optional for Ruby-style syntax
      consume(:THEN)
      body = parse_if_body
      branches << [condition, body]

      # Parse elif/elsif branches
      while peek(:ELIF) || peek(:ELSIF)
        consume(:ELIF) || consume(:ELSIF)
        elif_condition = parse_conditional_for_if
        skip_semicolon
        # 'then' is optional for Ruby-style syntax
        consume(:THEN)
        elif_body = parse_if_body
        branches << [elif_condition, elif_body]
      end

      # Parse else branch
      else_body = nil
      if peek(:ELSE)
        consume(:ELSE)
        else_body = parse_if_body
      end

      consume_end_or(:FI) || raise('Expected "fi" or "end" to close if statement')

      cmd = AST::If.new(branches: branches, else_body: else_body)
      parse_redirections(cmd)
    end

    # unless_statement : UNLESS conditional [THEN] body (ELSE body)? 'end'
    # Ruby-style unless (no elif support)
    def parse_unless
      consume(:UNLESS)

      condition = parse_conditional_for_if
      skip_semicolon
      # 'then' is optional for Ruby-style syntax
      consume(:THEN)
      body = parse_unless_body
      skip_semicolon

      # Parse optional else branch
      else_body = nil
      if peek(:ELSE)
        consume(:ELSE)
        else_body = parse_unless_body
      end

      consume_word('end') || raise('Expected "end" to close unless statement')

      cmd = AST::Unless.new(condition: condition, body: body, else_body: else_body)
      parse_redirections(cmd)
    end

    # Parse body of unless (stops at else/end)
    def parse_unless_body
      commands = []
      skip_semicolon

      while !peek(:ELSE) && !peek_end && current
        cmd = parse_conditional
        break unless cmd

        commands << cmd
        skip_semicolon
      end

      commands.length == 1 ? commands.first : AST::List.new(commands)
    end

    def skip_semicolon
      consume(:SEMICOLON) if peek(:SEMICOLON)
    end

    # Parse condition for if/elif (stops at then/do)
    def parse_conditional_for_if
      # Check for Ruby block condition: { expression }
      if peek(:RUBY_CONDITION)
        return parse_ruby_condition
      end

      left = parse_pipeline
      return nil unless left

      while peek(:AND) || peek(:OR)
        op = consume
        right = parse_pipeline
        left = if op.type == :AND
                 AST::And.new(left, right)
               else
                 AST::Or.new(left, right)
               end
      end

      left
    end

    # Parse Ruby block condition: { expression }
    def parse_ruby_condition
      if peek(:RUBY_CONDITION)
        token = consume(:RUBY_CONDITION)
        return AST::RubyCondition.new(expression: token.value)
      end

      # Fallback for compatibility (shouldn't normally be reached)
      consume(:LBRACE)
      expression = +''
      brace_depth = 1

      while current && brace_depth > 0
        if current.type == :LBRACE
          brace_depth += 1
          expression << '{'
        elsif current.type == :RBRACE
          brace_depth -= 1
          expression << '}' if brace_depth > 0
        else
          expression << current.value.to_s
          expression << ' '
        end
        consume
      end

      AST::RubyCondition.new(expression: expression.strip)
    end

    # Parse body of if/elif/elsif/else (stops at elif/elsif/else/fi/end)
    def parse_if_body
      commands = []
      skip_semicolon

      while !peek(:ELIF) && !peek(:ELSIF) && !peek(:ELSE) && !peek(:FI) && !peek_end && current
        cmd = parse_conditional
        break unless cmd

        commands << cmd
        skip_semicolon
      end

      commands.length == 1 ? commands.first : AST::List.new(commands)
    end

    # while_statement : WHILE conditional 'do' body 'done'
    def parse_while
      consume(:WHILE)

      condition = parse_conditional_for_if
      skip_semicolon
      consume_word('do') || raise('Expected "do" after while condition')
      body = parse_while_body
      consume_done_or_end || raise('Expected "done" or "end" to close while loop')

      AST::While.new(condition, body)
    end

    # until_statement : UNTIL conditional 'do' body 'done'
    def parse_until
      consume(:UNTIL)

      condition = parse_conditional_for_if
      skip_semicolon
      consume_word('do') || raise('Expected "do" after until condition')
      body = parse_while_body  # Reuse while body parser (stops at done)
      consume_done_or_end || raise('Expected "done" or "end" to close until loop')

      AST::Until.new(condition, body)
    end

    # Parse body of while loop (stops at done/end)
    def parse_while_body
      commands = []
      skip_semicolon

      while !peek_word('done') && !peek_end && current
        cmd = parse_conditional
        break unless cmd

        commands << cmd
        skip_semicolon
      end

      commands.length == 1 ? commands.first : AST::List.new(commands)
    end

    # for_statement : FOR WORD 'in' items 'do' body 'done'
    #               | FOR '((' init ';' cond ';' update '))' 'do' body 'done'
    def parse_for
      consume(:FOR)

      # Check for C-style arithmetic for loop: for ((init; cond; update))
      if peek(:ARITH_CMD)
        return parse_arith_for
      end

      variable = consume(:WORD)&.value || raise('Expected variable name after "for"')
      consume_word('in') || raise('Expected "in" after for variable')

      # Parse items until 'do' or ';'
      items = []
      while !peek_word('do') && !peek(:SEMICOLON) && peek(:WORD)
        items << consume(:WORD).value
      end

      skip_semicolon
      consume_word('do') || raise('Expected "do" after for items')
      body = parse_while_body  # Reuse while body parser (stops at done/end)
      consume_done_or_end || raise('Expected "done" or "end" to close for loop')

      AST::For.new(variable, items, body)
    end

    # C-style arithmetic for loop: for ((init; cond; update)); do body; done
    def parse_arith_for
      arith_expr = consume(:ARITH_CMD).value

      # Split by semicolons to get init, condition, update
      # Be careful not to split inside nested parentheses
      parts = split_arith_for_parts(arith_expr)

      init = parts[0] || ''
      condition = parts[1] || ''
      update = parts[2] || ''

      skip_semicolon
      consume_word('do') || raise('Expected "do" after for ((...))' )
      body = parse_while_body
      consume_done_or_end || raise('Expected "done" or "end" to close for loop')

      AST::ArithFor.new(init, condition, update, body)
    end

    def split_arith_for_parts(expr)
      parts = []
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
        when ';'
          if depth == 0
            parts << current.strip
            current = +''
          else
            current << c
          end
        else
          current << c
        end
      end

      parts << current.strip unless current.strip.empty?
      parts
    end

    # select_statement : SELECT WORD 'in' items 'do' body 'done'
    def parse_select
      consume(:SELECT)

      variable = consume(:WORD)&.value || raise('Expected variable name after "select"')
      consume_word('in') || raise('Expected "in" after select variable')

      # Parse items until 'do' or ';'
      items = []
      while !peek_word('do') && !peek(:SEMICOLON) && peek(:WORD)
        items << consume(:WORD).value
      end

      skip_semicolon
      consume_word('do') || raise('Expected "do" after select items')
      body = parse_while_body  # Reuse while body parser (stops at done/end)
      consume_done_or_end || raise('Expected "done" or "end" to close select loop')

      AST::Select.new(variable, items, body)
    end

    # case_statement : CASE WORD ['in'] (pattern ('|' pattern)* ')' body (';;'|';&'|';;&'))* ESAC
    #                | CASE WORD (WHEN pattern (',' pattern)* body)* [ELSE body] 'end'
    # Terminators (shell-style only):
    #   ;; - standard terminator (stop case)
    #   ;& - fall-through to next body (without testing pattern)
    #   ;;& - continue testing next patterns
    def parse_case
      consume(:CASE)

      # Check if case value is a Ruby expression block or a regular word
      if peek(:RUBY_CONDITION)
        # case { ruby_expr } in ... esac
        word = parse_ruby_condition
      else
        word = consume(:WORD)&.value || raise('Expected word or { expression } after "case"')
      end
      skip_semicolon

      # Check if using Ruby-style (when) or shell-style (in)
      ruby_style = peek(:WHEN)
      unless ruby_style
        consume_word('in') || raise('Expected "in" or "when" after case word')
        skip_semicolon
      end

      branches = []

      if ruby_style
        # Ruby-style: case value when pattern ... end
        while peek(:WHEN)
          consume(:WHEN)

          # Parse patterns (separated by , or |)
          patterns = parse_when_patterns
          break if patterns.empty?

          skip_semicolon
          body = parse_when_body
          branches << [patterns, body, nil]
        end

        # Parse optional else branch
        if peek(:ELSE)
          consume(:ELSE)
          skip_semicolon
          else_body = parse_when_body
          branches << [['*'], else_body, nil]
        end
      else
        # Shell-style: case value in pattern) ... ;; esac

        while !peek(:ESAC) && !peek_end && current
          # Parse patterns (separated by |)
          patterns = []
          loop do
            pattern = consume(:WORD)&.value
            break unless pattern

            patterns << pattern
            break unless peek(:PIPE)

            consume(:PIPE)
          end

          break if patterns.empty?

          # Consume closing )
          consume(:RPAREN) || raise('Expected ")" after case pattern')

          # Parse body until terminator (;;, ;&, ;;&) or esac
          body = parse_case_body

          # Determine terminator type
          terminator = nil
          if peek(:DOUBLE_SEMI)
            consume(:DOUBLE_SEMI)
            terminator = :double_semi
            skip_semicolon
          elsif peek(:CASE_FALL)
            consume(:CASE_FALL)
            terminator = :fall
            skip_semicolon
          elsif peek(:CASE_CONT)
            consume(:CASE_CONT)
            terminator = :cont
            skip_semicolon
          end

          branches << [patterns, body, terminator]
        end
      end

      consume_end_or(:ESAC) || raise('Expected "esac" or "end" to close case statement')

      AST::Case.new(word, branches)
    end

    # Parse switch statement with Ruby conditions
    # Parse patterns for Ruby-style when (separated by , or |)
    def parse_when_patterns
      patterns = []
      loop do
        pattern = consume(:WORD)&.value
        break unless pattern

        # Handle trailing comma (e.g., "foo," becomes "foo" and continues)
        if pattern.end_with?(',')
          patterns << pattern.chomp(',')
          next
        end

        patterns << pattern

        # Allow both , and | as separators
        if peek(:PIPE)
          consume(:PIPE)
        elsif peek_word(',')
          consume(:WORD)  # consume the comma as word
        else
          break
        end
      end
      patterns
    end

    # Parse body of when clause (stops at when/else/end)
    def parse_when_body
      commands = []
      skip_semicolon

      while !peek(:WHEN) && !peek(:ELSE) && !peek_end && current
        cmd = parse_conditional
        break unless cmd

        commands << cmd
        skip_semicolon
      end

      commands.length == 1 ? commands.first : AST::List.new(commands)
    end

    # subshell : '(' list ')'
    def parse_subshell
      consume(:LPAREN)
      body = parse_subshell_body
      consume(:RPAREN) || raise('Expected ")" to close subshell')
      cmd = AST::Subshell.new(body)
      parse_redirections(cmd)
    end

    # Parse body of subshell (stops at ))
    def parse_subshell_body
      commands = []
      skip_semicolon

      while !peek(:RPAREN) && current
        cmd = parse_conditional
        break unless cmd

        commands << cmd
        skip_semicolon
      end

      commands.length == 1 ? commands.first : AST::List.new(commands)
    end

    # coproc : COPROC [NAME] command
    # If first word after coproc is a simple name (not a command), use it as coproc name
    def parse_coproc
      consume(:COPROC)

      name = 'COPROC'

      # Look ahead: if we have a WORD followed by another WORD or control structure,
      # the first WORD is the coproc name
      if peek(:WORD)
        # Peek at the next token to decide if this WORD is a name or the command
        saved_pos = @pos
        first_word = consume(:WORD).value

        if peek_any(:WORD, :IF, :WHILE, :FOR, :UNTIL, :SELECT, :CASE, :FUNCTION, :LPAREN, :LBRACE)
          # First word is the name, next is the command
          name = first_word
        else
          # First word is the command itself, restore position
          @pos = saved_pos
        end
      end

      # Parse the command (can be a simple command or compound command)
      command = parse_command
      raise 'Expected command after coproc' unless command

      AST::Coproc.new(name: name, command: command)
    end

    # lazy_load : LAZY_LOAD '{' commands '}'
    # Parses lazy_load block to run commands in background
    def parse_lazy_load
      consume(:LAZY_LOAD)

      unless peek(:LBRACE)
        raise "Expected '{' after lazy_load"
      end
      consume(:LBRACE)

      # Skip leading semicolons/newlines (from source joining lines with "; ")
      consume(:SEMICOLON) while peek(:SEMICOLON)
      consume(:NEWLINE) while peek(:NEWLINE)

      # Parse the body as a command list
      body = parse_list

      # Skip trailing semicolons before closing brace
      consume(:SEMICOLON) while peek(:SEMICOLON)
      consume(:NEWLINE) while peek(:NEWLINE)

      unless peek(:RBRACE)
        raise "Expected '}' to close lazy_load"
      end
      consume(:RBRACE)

      AST::LazyLoad.new(body: body)
    end

    # conditional_expr : '[[' expression ']]'
    # Parses extended test command [[ expression ]]
    def parse_conditional_expr
      consume(:DOUBLE_LBRACKET)

      # Collect all tokens until ]]
      expression = []
      until peek(:DOUBLE_RBRACKET) || @pos >= @tokens.length
        token = consume
        expression << token
      end

      consume(:DOUBLE_RBRACKET) || raise('Expected "]]" to close conditional expression')

      AST::ConditionalExpr.new(expression)
    end

    # arithmetic_command : '((' expression '))'
    # Parses arithmetic command (( expression ))
    def parse_arithmetic_command
      token = consume(:ARITH_CMD)
      AST::ArithmeticCommand.new(token.value)
    end

    # Parse array assignment: VAR=(a b c) or VAR+=(d e)
    def parse_array_assign
      token = consume(:ARRAY_ASSIGN)
      AST::ArrayAssign.new(var: token.value[:var], elements: token.value[:elements])
    end

    # Parse function call syntax: cmd(arg1, arg2)
    def parse_func_call
      token = consume(:FUNC_CALL)
      name = token.value[:name]
      args = token.value[:args]

      # Transform args for head/tail: convert bare positive integers to -n form
      # e.g., head(5) -> head -n 5, tail(10) -> tail -n 10
      if name == 'head' || name == 'tail'
        args = transform_head_tail_args(args)
      end

      # Check for trailing block
      block = nil
      if peek(:BLOCK)
        block = consume(:BLOCK).value
      end

      cmd = AST::Command.new(name: name, args: args, block: block, env: [])
      parse_redirections(cmd)
    end

    # Transform head/tail args: bare positive integers become -n <number>
    def transform_head_tail_args(args)
      transformed = []
      skip_transform = false

      args.each do |arg|
        if skip_transform
          transformed << arg
          skip_transform = false
        elsif arg == '-n' || arg == '-c'
          transformed << arg
          skip_transform = true
        elsif arg =~ /\A\d+\z/
          transformed << '-n'
          transformed << arg
        else
          transformed << arg
        end
      end

      transformed
    end

    # Parse body of case branch (stops at ;;, ;&, ;;&, esac, or end)
    def parse_case_body
      commands = []
      skip_semicolon

      while !peek(:DOUBLE_SEMI) && !peek(:CASE_FALL) && !peek(:CASE_CONT) && !peek(:ESAC) && !peek_end && current
        cmd = parse_conditional
        break unless cmd

        commands << cmd
        skip_semicolon
      end

      commands.length == 1 ? commands.first : AST::List.new(commands)
    end

    def peek_word(value)
      peek(:WORD) && current.value == value
    end

    def consume_word(value)
      return nil unless peek_word(value)

      consume(:WORD)
    end

    # Ruby-style 'end' can be used instead of fi/done/esac
    def peek_end
      peek_word('end')
    end

    # Consume 'end' as alternative to fi/esac
    def consume_end_or(type)
      consume(type) || consume_word('end')
    end

    # Consume 'done' or 'end'
    def consume_done_or_end
      consume_word('done') || consume_word('end')
    end

    def parse_arg
      token = consume
      case token.type
      when :WORD
        token.value
      when :ARRAY
        AST::ArrayLiteral.new(token.value)
      when :PROC_SUB_IN
        AST::ProcessSubstitution.new(token.value, :in)
      when :PROC_SUB_OUT
        AST::ProcessSubstitution.new(token.value, :out)
      end
    end

    def parse_redirections(cmd)
      while peek(:REDIRECT_OUT) || peek(:REDIRECT_CLOBBER) || peek(:REDIRECT_APPEND) ||
            peek(:REDIRECT_IN) || peek(:REDIRECT_ERR) || peek(:DUP_OUT) || peek(:DUP_IN) ||
            peek(:HEREDOC) || peek(:HEREDOC_INDENT) || peek(:HERESTRING) ||
            peek(:VARNAME_REDIRECT)
        op = consume

        case op.type
        when :HEREDOC, :HEREDOC_INDENT
          # Parse heredoc delimiter info from token value
          # Format: "DELIMITER" or "DELIMITER:quoted"
          delimiter_info = op.value
          if delimiter_info.end_with?(':quoted')
            delimiter = delimiter_info.sub(/:quoted$/, '')
            expand = false
          else
            delimiter = delimiter_info
            expand = true
          end
          strip_tabs = (op.type == :HEREDOC_INDENT)
          cmd = AST::Heredoc.new(command: cmd, delimiter: delimiter, expand: expand, strip_tabs: strip_tabs)
        when :HERESTRING
          # The token value contains the string
          cmd = AST::Herestring.new(cmd, op.value)
        when :VARNAME_REDIRECT
          # {varname}>file or {varname}<file - allocates FD to variable
          varname = op.value[:varname]
          redirect_op = op.value[:operator]
          target = consume(:WORD)&.value
          cmd = AST::VarnameRedirect.new(cmd, varname, redirect_op, target) if target
        else
          # Regular redirections (>, >>, <, 2>, >&, <&)
          target = consume(:WORD)&.value
          cmd = AST::Redirect.new(cmd, op.value, target) if target
        end
      end
      cmd
    end
  end
end
