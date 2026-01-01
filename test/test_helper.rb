# frozen_string_literal: true

require 'test/unit'
require_relative '../lib/rubish'

# Common test helper methods
module TestHelper
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
