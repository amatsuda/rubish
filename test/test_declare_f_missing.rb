# frozen_string_literal: true

require_relative 'test_helper'

# declare -f / -F on a name that is not a function is silent, status 1
class TestDeclareFMissing < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_declare_capital_f_unknown_function_is_silent
    out = capture_output { execute('declare -F no_such_function_xyz') }
    assert_equal '', out
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_declare_f_unknown_function_is_silent
    out = capture_output { execute('declare -f no_such_function_xyz') }
    assert_equal '', out
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end
end
