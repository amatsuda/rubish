# frozen_string_literal: true

require_relative 'test_helper'

# $_ holds the last argument of the previous command
class TestLastArgument < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_last_argument_of_previous_builtin
    execute('echo first second')
    assert_equal 'second', get_shell_var('_')
  end

  def test_last_argument_of_previous_external_command
    execute('true alpha beta')
    assert_equal 'beta', get_shell_var('_')
  end

  def test_command_name_when_there_are_no_arguments
    execute('true')
    assert_equal 'true', get_shell_var('_')
  end

  def test_inside_a_list
    out = capture_stdout { execute('echo one two; echo "$_"') }
    assert_equal "one two\ntwo\n", out
  end
end
