# frozen_string_literal: true

module Rubish
  module AST
    # Single command: ls -la
    # env: prefix environment variables (e.g., FOO=bar cmd)
    Command = Data.define(:name, :args, :block, :env) do
      def initialize(name:, args: [], block: nil, env: [])
        super
      end
    end

    # Pipeline: cmd1 | cmd2 | cmd3
    # pipe_types: array of :pipe or :pipe_both (for |&) indicating connection type between commands
    # If nil or empty, all pipes are regular pipes
    Pipeline = Data.define(:commands, :pipe_types) do
      def initialize(commands:, pipe_types: nil)
        super
      end
    end

    # Negation: ! pipeline - negates exit status of pipeline
    Negation = Data.define(:command)

    # Command list: cmd1 ; cmd2
    List = Data.define(:commands)

    # Redirect: cmd > file
    Redirect = Data.define(:command, :operator, :target)

    # VarnameRedirect: cmd {fd}>file - allocates FD to variable
    # varname: the variable name to store the allocated FD
    # operator: the redirection operator (>, >>, <, >&, <&)
    # target: the file or FD number
    VarnameRedirect = Data.define(:command, :varname, :operator, :target)

    # Background: cmd &
    Background = Data.define(:command)

    # Conditional: cmd1 && cmd2
    And = Data.define(:left, :right)

    # Conditional: cmd1 || cmd2
    Or = Data.define(:left, :right)

    # Ruby literals as arguments
    ArrayLiteral = Data.define(:value)   # [1, 2, 3]
    RegexpLiteral = Data.define(:value)  # /pattern/

    # Process substitution: <(cmd) or >(cmd)
    # direction: :in for <(cmd), :out for >(cmd)
    ProcessSubstitution = Data.define(:command, :direction)

    # If statement: if cond; then body; elif cond; then body; else body; fi
    # branches is array of [condition, body] pairs, else_body is optional
    If = Data.define(:branches, :else_body) do
      def initialize(branches:, else_body: nil)
        super
      end
    end

    # Unless statement (Ruby-style): unless cond ... else ... end
    # Executes body when condition is false (opposite of if)
    Unless = Data.define(:condition, :body, :else_body) do
      def initialize(condition:, body:, else_body: nil)
        super
      end
    end

    # While loop: while cond; do body; done
    While = Data.define(:condition, :body)

    # Until loop: until cond; do body; done (loops while condition is false)
    Until = Data.define(:condition, :body)

    # For loop: for var in items; do body; done
    For = Data.define(:variable, :items, :body)

    # C-style arithmetic for loop: for ((init; cond; update)); do body; done
    ArithFor = Data.define(:init, :condition, :update, :body)

    # Select loop: select var in items; do body; done
    Select = Data.define(:variable, :items, :body)

    # Function definition: function name { body } or name() { body } or def name(params); body; end
    # params is an optional array of parameter names for Ruby-style def with arguments
    Function = Data.define(:name, :body, :params)

    # Case statement: case word in pattern1) body ;; pattern2|pattern3) body ;; esac
    # branches is array of [patterns, body, terminator] where:
    #   - patterns is array of pattern strings
    #   - body is the AST for the branch body
    #   - terminator is :double_semi (;;), :fall (;&), :cont (;;&), or nil (last branch)
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

    # Coproc: coproc [NAME] command - runs command as coprocess with bidirectional pipes
    # name: the coprocess name (defaults to "COPROC")
    # command: the command to run
    Coproc = Data.define(:name, :command) do
      def initialize(name: 'COPROC', command:)
        super
      end
    end

    # Time: time [-p] pipeline - measure execution time of a command
    # posix_format: true if -p flag is used (POSIX format output)
    # command: the command/pipeline to time
    Time = Data.define(:command, :posix_format) do
      def initialize(command:, posix_format: false)
        super
      end
    end

    # ConditionalExpr: [[ expression ]] - extended test command
    # expression: array of tokens/strings representing the expression
    # Supports: string comparison (==, !=, <, >), pattern matching, regex (=~),
    #           file tests (-f, -d, -e, etc.), logical operators (&&, ||, !)
    ConditionalExpr = Data.define(:expression)

    # ArithmeticCommand: (( expression )) - arithmetic evaluation command
    # expression: the arithmetic expression string
    # Returns exit status 0 if result is non-zero, 1 if result is zero
    ArithmeticCommand = Data.define(:expression)

    # ArrayAssign: VAR=(a b c) or VAR+=(d e) - array assignment
    # var: the variable name with = or += (e.g., "arr=" or "arr+=")
    # elements: array of element strings
    ArrayAssign = Data.define(:var, :elements)
  end
end
