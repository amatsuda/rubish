# frozen_string_literal: true

module Rubish
  module AST
    # Single command: ls -la
    Command = Data.define(:name, :args, :block) do
      def initialize(name:, args: [], block: nil)
        super
      end
    end

    # Pipeline: cmd1 | cmd2 | cmd3
    Pipeline = Data.define(:commands)

    # Command list: cmd1 ; cmd2
    List = Data.define(:commands)

    # Redirect: cmd > file
    Redirect = Data.define(:command, :operator, :target)

    # Background: cmd &
    Background = Data.define(:command)

    # Conditional: cmd1 && cmd2
    And = Data.define(:left, :right)

    # Conditional: cmd1 || cmd2
    Or = Data.define(:left, :right)

    # Ruby literals as arguments
    ArrayLiteral = Data.define(:value)   # [1, 2, 3]
    RegexpLiteral = Data.define(:value)  # /pattern/

    # If statement: if cond; then body; elif cond; then body; else body; fi
    # branches is array of [condition, body] pairs, else_body is optional
    If = Data.define(:branches, :else_body) do
      def initialize(branches:, else_body: nil)
        super
      end
    end

    # While loop: while cond; do body; done
    While = Data.define(:condition, :body)

    # For loop: for var in items; do body; done
    For = Data.define(:variable, :items, :body)
  end
end
