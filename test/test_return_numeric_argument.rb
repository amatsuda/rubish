# frozen_string_literal: true

require_relative 'test_helper'

# `return abc` is an error: the function still returns, with status 2
class TestReturnNumericArgument < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_non_numeric_argument
    execute('f() { return abc; echo after; }')
    out = nil
    err = capture_stderr { out = capture_stdout { execute('f') } }
    assert_equal "rubish: return: abc: numeric argument required\n", err
    assert_equal '', out
    assert_equal 2, @repl.instance_variable_get(:@last_status)
  end

  def test_negative_number_is_accepted
    execute('f() { return -1; }')
    execute('f')
    assert_equal 255, @repl.instance_variable_get(:@last_status)
  end
end
