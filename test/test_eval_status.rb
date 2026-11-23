# frozen_string_literal: true

require_relative 'test_helper'

# eval's exit status is that of the last command it ran
class TestEvalStatus < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_failing_command
    out = capture_stdout { execute("eval 'false'; echo $?") }
    assert_equal "1\n", out
  end

  def test_last_command_of_several
    out = capture_stdout { execute("eval 'false; true'; echo $?; eval 'true; false'; echo $?") }
    assert_equal "0\n1\n", out
  end

  def test_function_return_code
    out = capture_stdout { execute("f() { return 7; }; eval f; echo $?") }
    assert_equal "7\n", out
  end
end
