# frozen_string_literal: true

require_relative 'test_helper'

# `unset name` removes the function of that name when no variable has it
class TestUnsetFunctionByName < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_function_is_removed
    out = capture_stdout { execute('f() { :; }; unset f; declare -F f; echo $?') }
    assert_equal "1\n", out
  end

  def test_variable_takes_precedence
    out = capture_stdout { execute('g() { echo fn; }; g=1; unset g; echo "[$g]"; g') }
    assert_equal "[]\nfn\n", out
  end

  def test_bare_unset_succeeds_quietly
    err = capture_stderr { @out = capture_stdout { execute('unset; echo $?') } }
    assert_equal "0\n", @out
    assert_equal '', err
  end
end
