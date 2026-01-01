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
  end
end
