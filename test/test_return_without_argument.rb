# frozen_string_literal: true

require_relative 'test_helper'

# A bare `return` returns the status of the last command run in the function
class TestReturnWithoutArgument < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_bare_return_keeps_failure_status
    execute('f_ret1() { false; return; }')
    execute('f_ret1')
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_bare_return_keeps_success_status
    execute('f_ret2() { false; true; return; }')
    execute('f_ret2')
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end
end
