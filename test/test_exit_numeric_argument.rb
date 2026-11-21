# frozen_string_literal: true

require_relative 'test_helper'

# exit with a non-numeric argument is an error with status 2
class TestExitNumericArgument < Test::Unit::TestCase
  def test_non_numeric_argument
    repl = Rubish::REPL.new
    status = nil
    # throw :exit unwinds through capture_stderr, so capture around the catch
    err = capture_stderr { status = catch(:exit) { repl.send(:execute, 'exit abc'); :not_exited } }
    assert_match(/exit: abc: numeric argument required/, err)
    assert_equal 2, status
  end
end
