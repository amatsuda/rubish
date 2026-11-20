# frozen_string_literal: true

require_relative 'test_helper'

# A background job's exit status (as seen by `wait`) is the status of the
# command it ran, not always 0
class TestBackgroundExitStatus < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  def test_wait_reports_failure_of_background_command
    capture_output { execute('false & wait $!') }
    assert_equal 1, last_status
  end

  def test_wait_reports_success_of_background_command
    capture_output { execute('true & wait $!') }
    assert_equal 0, last_status
  end

  def test_wait_reports_exit_code_of_background_subshell
    capture_output { execute('(exit 4) & wait $!') }
    assert_equal 4, last_status
  end
end
