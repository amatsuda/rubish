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
        if op.type == :AMPERSAND && !peek_any(:WORD, :ARRAY, :REGEXP, :IF)
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

    # command : if_statement | WORD arg* block? (redirection)*
    # arg : WORD | ARRAY | REGEXP
    def parse_command
      # Check for if statement
      return parse_if if peek(:IF)

      return nil unless peek(:WORD)

      name = consume(:WORD).value
      args = []

      # Parse arguments (WORD, ARRAY, REGEXP)
      while peek_any(:WORD, :ARRAY, :REGEXP)
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

    def parse_arg
      token = consume
      case token.type
      when :WORD
        token.value
      when :ARRAY
        AST::ArrayLiteral.new(token.value)
      when :REGEXP
        AST::RegexpLiteral.new(token.value)
      end
    end

    def parse_redirections(cmd)
      while peek(:REDIRECT_OUT) || peek(:REDIRECT_APPEND) ||
            peek(:REDIRECT_IN) || peek(:REDIRECT_ERR)
        op = consume
        target = consume(:WORD)&.value
        cmd = AST::Redirect.new(cmd, op.value, target) if target
      end
      cmd
    end
  end
end
