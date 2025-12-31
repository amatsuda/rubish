# frozen_string_literal: true

module Rubish
  module AST
    # Single command: ls -la
    Command = Data.define(:name, :args)

    # Pipeline: cmd1 | cmd2 | cmd3
    Pipeline = Data.define(:commands)

    # Command list: cmd1 ; cmd2
    List = Data.define(:commands)

    # Redirect: cmd > file
    Redirect = Data.define(:command, :operator, :target)

    # Background: cmd &
    Background = Data.define(:command)
  end
end
