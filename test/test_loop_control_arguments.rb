# frozen_string_literal: true

require_relative 'test_helper'

# break/continue validate their count like bash: 0 is out of range
# (status 1), a non-number is an error (status 2); neither leaves the loop
class TestLoopControlArguments < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_zero_is_out_of_range
    err = capture_stderr { @out = capture_stdout { execute('for i in 1 2; do break 0; echo $?; done') } }
    assert_equal "1\n1\n", @out
    assert_match(/break: 0: loop count out of range/, err)
  end

  def test_non_numeric_count
    err = capture_stderr { @out = capture_stdout { execute('for i in 1; do continue x; echo $?; done') } }
    assert_equal "2\n", @out
    assert_match(/continue: x: numeric argument required/, err)
  end
end
