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

    def consume(type = nil)
      return nil if @pos >= @tokens.length
      return nil if type && current.type != type

      token = current
      @pos += 1
      token
    end

    # list : pipeline ((';' | '&') pipeline)*
    def parse_list
      first = parse_pipeline
      return nil unless first

      commands = [first]
      while peek(:SEMICOLON) || peek(:AMPERSAND)
        op = consume
        if op.type == :AMPERSAND && !peek(:WORD)
          # Trailing &, make last command background
          commands[-1] = AST::Background.new(commands[-1])
          break
        end
        next_cmd = parse_pipeline
        commands << next_cmd if next_cmd
      end

      commands.length == 1 ? commands.first : AST::List.new(commands)
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

    # command : WORD+ (redirection)*
    def parse_command
      return nil unless peek(:WORD)

      name = consume(:WORD).value
      args = []
      args << consume(:WORD).value while peek(:WORD)

      cmd = AST::Command.new(name, args)
      parse_redirections(cmd)
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
