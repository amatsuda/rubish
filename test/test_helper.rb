# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rubish'

require 'test-unit'

# Initialize Builtins with a default ShellState so that tests calling
# Builtins.run() directly (without creating a REPL) work correctly.
unless Rubish::Builtins.current_state
  Rubish::Builtins.current_state = Rubish::ShellState.new
end

# Common test helper methods
module TestHelper
  # Get a shell variable value (from shell_vars or ENV)
  def get_shell_var(name)
    Rubish::Builtins.get_var(name)
  end

  # Set a shell variable (via the shell's variable store)
  def set_shell_var(name, value)
    Rubish::Builtins.set_var(name, value)
  end

  # Capture stdout during block execution
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  # Capture stderr during block execution
  def capture_stderr
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original_stderr
  end

  # Capture both stdout and stderr during block execution
  def capture_output
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    $stdout.string + $stderr.string
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  # Execute a line via the REPL (requires @repl to be set)
  def execute(line)
    @repl.send(:execute, line)
  end
end

Test::Unit::TestCase.include TestHelper
