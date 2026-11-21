# frozen_string_literal: true

require_relative 'test_helper'

# `[[ ]]` and `(( ))` accept redirections like any other command
class TestConditionalRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_conditional_with_stderr_redirect_in_a_list
    out = capture_stdout { execute('[[ 10 -eq 10.0 ]] 2>/dev/null || echo noteq') }
    assert_equal "noteq\n", out
  end

  def test_arithmetic_command_with_stdout_redirect
    execute('(( 1 )) > /dev/null && r=yes')
    assert_equal 'yes', get_shell_var('r')
  end

  def test_lone_conditional_with_redirect
    execute('[[ a < b ]] 2>/dev/null')
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end
end
