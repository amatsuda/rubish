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
        if op.type == :AMPERSAND && !peek_any(:WORD, :ARRAY, :REGEXP, :IF, :WHILE, :FOR)
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

    # pipeline : command ('|' command)*
    def parse_pipeline
      first = parse_command
      return nil unless first

      commands = [first]
      while peek(:PIPE)
        consume(:PIPE)
        cmd = parse_command
        commands << cmd if cmd
      end

      commands.length == 1 ? commands.first : AST::Pipeline.new(commands)
    end

    # command : if_statement | while_statement | until_statement | for_statement | case_statement | function_def | subshell | coproc | WORD arg* block? (redirection)*
    # arg : WORD | ARRAY | REGEXP
    def parse_command
      # Check for control structures
      return parse_if if peek(:IF)
      return parse_while if peek(:WHILE)
      return parse_until if peek(:UNTIL)
      return parse_for if peek(:FOR)
      return parse_select if peek(:SELECT)
      return parse_case if peek(:CASE)
      return parse_function_keyword if peek(:FUNCTION)
      return parse_subshell if peek(:LPAREN)
      return parse_coproc if peek(:COPROC)

      return nil unless peek(:WORD)

      name = consume(:WORD).value

      # Check for function definition: name() { body }
      if peek(:PARENS)
        consume(:PARENS)
        return parse_function_body(name)
      end

      args = []

      # Parse arguments (WORD, ARRAY, REGEXP, PROC_SUB_IN, PROC_SUB_OUT)
      while peek_any(:WORD, :ARRAY, :REGEXP, :PROC_SUB_IN, :PROC_SUB_OUT)
        args << parse_arg
      end

      # Parse optional block
      block = nil
      if peek(:BLOCK)
        block = consume(:BLOCK).value
      end

      cmd = AST::Command.new(name: name, args: args, block: block)
      parse_redirections(cmd)
    end

    # function_def : FUNCTION WORD '{' body '}'
    def parse_function_keyword
      consume(:FUNCTION)
      name = consume(:WORD)&.value || raise('Expected function name after "function"')
      parse_function_body(name)
    end

    # Parse function body: { commands }
    def parse_function_body(name)
      consume(:LBRACE) || raise('Expected "{" for function body')
      body = parse_function_body_commands
      consume(:RBRACE) || raise('Expected "}" to close function body')
      AST::Function.new(name, body)
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

    # if_statement : IF conditional THEN body (ELIF conditional THEN body)* (ELSE body)? FI
    def parse_if
      consume(:IF)
      branches = []

      # Parse first branch
      condition = parse_conditional_for_if
      skip_semicolon
      consume(:THEN) || raise('Expected "then" after if condition')
      body = parse_if_body
      branches << [condition, body]

      # Parse elif branches
      while peek(:ELIF)
        consume(:ELIF)
        elif_condition = parse_conditional_for_if
        skip_semicolon
        consume(:THEN) || raise('Expected "then" after elif condition')
        elif_body = parse_if_body
        branches << [elif_condition, elif_body]
      end

      # Parse else branch
      else_body = nil
      if peek(:ELSE)
        consume(:ELSE)
        else_body = parse_if_body
      end

      consume(:FI) || raise('Expected "fi" to close if statement')

      AST::If.new(branches: branches, else_body: else_body)
    end

    def skip_semicolon
      consume(:SEMICOLON) if peek(:SEMICOLON)
    end

    # Parse condition for if/elif (stops at then/do)
    def parse_conditional_for_if
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

    # Parse body of if/elif/else (stops at elif/else/fi)
    def parse_if_body
      commands = []
      skip_semicolon

      while !peek(:ELIF) && !peek(:ELSE) && !peek(:FI) && current
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
      consume_word('done') || raise('Expected "done" to close while loop')

      AST::While.new(condition, body)
    end

    # until_statement : UNTIL conditional 'do' body 'done'
    def parse_until
      consume(:UNTIL)

      condition = parse_conditional_for_if
      skip_semicolon
      consume_word('do') || raise('Expected "do" after until condition')
      body = parse_while_body  # Reuse while body parser (stops at done)
      consume_word('done') || raise('Expected "done" to close until loop')

      AST::Until.new(condition, body)
    end

    # Parse body of while loop (stops at done)
    def parse_while_body
      commands = []
      skip_semicolon

      while !peek_word('done') && current
        cmd = parse_conditional
        break unless cmd

        commands << cmd
        skip_semicolon
      end

      commands.length == 1 ? commands.first : AST::List.new(commands)
    end

    # for_statement : FOR WORD 'in' items 'do' body 'done'
    def parse_for
      consume(:FOR)

      variable = consume(:WORD)&.value || raise('Expected variable name after "for"')
      consume_word('in') || raise('Expected "in" after for variable')

      # Parse items until 'do' or ';'
      items = []
      while !peek_word('do') && !peek(:SEMICOLON) && peek(:WORD)
        items << consume(:WORD).value
      end

      skip_semicolon
      consume_word('do') || raise('Expected "do" after for items')
      body = parse_while_body  # Reuse while body parser (stops at done)
      consume_word('done') || raise('Expected "done" to close for loop')

      AST::For.new(variable, items, body)
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
      body = parse_while_body  # Reuse while body parser (stops at done)
      consume_word('done') || raise('Expected "done" to close select loop')

      AST::Select.new(variable, items, body)
    end

    # case_statement : CASE WORD 'in' (pattern ('|' pattern)* ')' body ';;')* ESAC
    def parse_case
      consume(:CASE)

      word = consume(:WORD)&.value || raise('Expected word after "case"')
      skip_semicolon
      consume_word('in') || raise('Expected "in" after case word')
      skip_semicolon

      branches = []

      while !peek(:ESAC) && current
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

        # Parse body until ;;
        body = parse_case_body
        branches << [patterns, body]

        # Consume ;;
        if peek(:DOUBLE_SEMI)
          consume(:DOUBLE_SEMI)
          skip_semicolon
        end
      end

      consume(:ESAC) || raise('Expected "esac" to close case statement')

      AST::Case.new(word, branches)
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

    # Parse body of case branch (stops at ;; or esac)
    def parse_case_body
      commands = []
      skip_semicolon

      while !peek(:DOUBLE_SEMI) && !peek(:ESAC) && current
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

    def parse_arg
      token = consume
      case token.type
      when :WORD
        token.value
      when :ARRAY
        AST::ArrayLiteral.new(token.value)
      when :REGEXP
        AST::RegexpLiteral.new(token.value)
      when :PROC_SUB_IN
        AST::ProcessSubstitution.new(token.value, :in)
      when :PROC_SUB_OUT
        AST::ProcessSubstitution.new(token.value, :out)
      end
    end

    def parse_redirections(cmd)
      while peek(:REDIRECT_OUT) || peek(:REDIRECT_CLOBBER) || peek(:REDIRECT_APPEND) ||
            peek(:REDIRECT_IN) || peek(:REDIRECT_ERR) ||
            peek(:HEREDOC) || peek(:HEREDOC_INDENT) || peek(:HERESTRING)
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
        else
          # Regular redirections
          target = consume(:WORD)&.value
          cmd = AST::Redirect.new(cmd, op.value, target) if target
        end
      end
      cmd
    end
  end
end
