# frozen_string_literal: true

require_relative 'test_helper'

# `VAR=value f` makes VAR visible inside the function f for that call, and
# restores it afterwards, as in bash
class TestPrefixEnvFunction < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_prefix_assignment_is_visible_in_the_function
    out = capture_stdout { execute('f() { echo "[$V]"; }; V=fv f; echo "[$V]"') }
    assert_equal "[fv]\n[]\n", out
  end

  def test_prefix_assignment_shadows_the_outer_value
    out = capture_stdout { execute('f() { echo "[$V]"; }; V=outer; V=inner f; echo "[$V]"') }
    assert_equal "[inner]\n[outer]\n", out
  end

  def test_prefix_assignment_in_a_compound_command
    out = capture_stdout { execute('f() { echo "[$V]"; }; { V=fv f; }; echo "[$V]"') }
    assert_equal "[fv]\n[]\n", out
  end
end
