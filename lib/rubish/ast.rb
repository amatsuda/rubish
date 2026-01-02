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

    # Until loop: until cond; do body; done (loops while condition is false)
    Until = Data.define(:condition, :body)

    # For loop: for var in items; do body; done
    For = Data.define(:variable, :items, :body)

    # Function definition: function name { body } or name() { body }
    Function = Data.define(:name, :body)

    # Case statement: case word in pattern1) body ;; pattern2|pattern3) body ;; esac
    # branches is array of [patterns, body] where patterns is array of pattern strings
    Case = Data.define(:word, :branches)

    # Subshell: (commands) - runs commands in a child process
    Subshell = Data.define(:body)

    # Heredoc: cmd <<EOF ... EOF - provides multi-line input to command
    # delimiter: the terminating word (e.g., "EOF")
    # content: the heredoc content (set later when lines are collected)
    # expand: true if variables should be expanded
    # strip_tabs: true for <<- (allows indented delimiter)
    Heredoc = Data.define(:command, :delimiter, :content, :expand, :strip_tabs) do
      def initialize(command:, delimiter:, content: nil, expand: true, strip_tabs: false)
        super
      end

      def with_content(new_content)
        Heredoc.new(command: command, delimiter: delimiter, content: new_content, expand: expand, strip_tabs: strip_tabs)
      end
    end

    # Herestring: cmd <<< "string" - provides single-line string as stdin
    Herestring = Data.define(:command, :string)
  end
end
