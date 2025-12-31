# frozen_string_literal: true

module Rubish
  class Lexer
    Token = Data.define(:type, :value)

    OPERATORS = {
      '|' => :PIPE,
      ';' => :SEMICOLON,
      '&' => :AMPERSAND,
      '>' => :REDIRECT_OUT,
      '>>' => :REDIRECT_APPEND,
      '<' => :REDIRECT_IN,
      '2>' => :REDIRECT_ERR
    }.freeze

    def initialize(input)
      @input = input
      @pos = 0
    end

    def tokenize
      tokens = []
      while @pos < @input.length
        skip_whitespace
        break if @pos >= @input.length

        token = read_token
        tokens << token if token
      end
      tokens
    end

    private

    def skip_whitespace
      @pos += 1 while @pos < @input.length && @input[@pos] =~ /[ \t]/
    end

    def read_token
      # Check for multi-char operators first
      if @input[@pos, 2] == '>>'
        @pos += 2
        return Token.new(:REDIRECT_APPEND, '>>')
      end

      if @input[@pos, 2] == '2>'
        @pos += 2
        return Token.new(:REDIRECT_ERR, '2>')
      end

      # Single char operators
      char = @input[@pos]
      if OPERATORS.key?(char)
        @pos += 1
        return Token.new(OPERATORS[char], char)
      end

      # Word (command or argument)
      read_word
    end

    def read_word
      start = @pos
      while @pos < @input.length
        char = @input[@pos]
        break if char =~ /[ \t]/ || OPERATORS.key?(char)
        break if @input[@pos, 2] == '>>' || @input[@pos, 2] == '2>'

        if char == '"'
          read_double_quoted_string
        elsif char == "'"
          read_single_quoted_string
        else
          @pos += 1
        end
      end
      value = @input[start...@pos]
      Token.new(:WORD, value) unless value.empty?
    end

    def read_double_quoted_string
      @pos += 1 # skip opening "
      while @pos < @input.length && @input[@pos] != '"'
        @pos += 2 if @input[@pos] == '\\' # skip escaped char
        @pos += 1
      end
      @pos += 1 # skip closing "
    end

    def read_single_quoted_string
      @pos += 1 # skip opening '
      @pos += 1 while @pos < @input.length && @input[@pos] != "'"
      @pos += 1 # skip closing '
    end
  end
end
