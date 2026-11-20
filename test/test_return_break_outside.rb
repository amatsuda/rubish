# frozen_string_literal: true

require_relative 'test_helper'

# return/break/continue outside a function or loop report an error instead of
# raising UncaughtThrowError
class TestReturnBreakOutside < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  def test_return_outside_function_reports_error_and_fails
    err = capture_stderr { execute('return 5') }
    assert_match(/return: can only `return' from a function or sourced script/, err)
    assert_equal 1, last_status
  end

  def test_return_outside_function_does_not_stop_the_list
    out = capture_output { execute('return 5; echo still_here') }
    assert_match(/still_here/, out)
  end

  def test_break_outside_loop_reports_error
    err = capture_stderr { execute('break') }
    assert_match(/break: only meaningful in a `for', `while', or `until' loop/, err)
  end

  def test_continue_outside_loop_reports_error
    err = capture_stderr { execute('continue') }
    assert_match(/continue: only meaningful in a `for', `while', or `until' loop/, err)
  end

  def test_return_inside_function_still_works
    execute('f() { return 3; }')
    capture_stderr { execute('f') }
    assert_equal 3, last_status
  end

  def test_break_inside_loop_still_works
    out = capture_stdout { execute('for i in 1 2 3; do echo $i; break; done') }
    assert_equal "1\n", out
  end
end
