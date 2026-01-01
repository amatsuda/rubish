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
        if op.type == :AMPERSAND && !peek_any(:WORD, :ARRAY, :REGEXP)
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

    # command : WORD arg* block? (redirection)*
    # arg : WORD | ARRAY | REGEXP
    def parse_command
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
