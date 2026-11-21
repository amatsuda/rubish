# frozen_string_literal: true

require_relative 'test_helper'

class TestCaseAttributeAssignment < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  # -l and -u attributes apply to later plain assignments too
  def test_case_attributes_apply_on_assignment
    execute('declare -l low_a; low_a=HeLLo; declare -u up_a; up_a=hello')
    assert_equal 'hello', get_shell_var('low_a')
    assert_equal 'HELLO', get_shell_var('up_a')
  end
end
