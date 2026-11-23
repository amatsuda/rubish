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
    # bash 5.3 reports the argument and goes on with status 2
    assert_equal :not_exited, status
    assert_equal 2, repl.instance_variable_get(:@last_status)
  end
end
