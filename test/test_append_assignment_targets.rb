# frozen_string_literal: true

require_relative 'test_helper'

# `VAR+=word` on an indexed array appends to element 0, and on an unset
# variable behaves like a plain assignment
class TestAppendAssignmentTargets < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_append_to_an_array_extends_its_first_element
    out = capture_stdout { execute('a=(x y); a+=z; echo ${a[0]} ${#a[@]}') }
    assert_equal "xz 2\n", out
  end

  def test_append_to_an_unset_variable_assigns_it
    out = capture_stdout { execute('unset u; u+=z; echo "$u"') }
    assert_equal "z\n", out
  end

  def test_append_to_an_unset_variable_in_a_compound_command
    out = capture_stdout { execute('unset u; { u+=z; }; echo "$u"') }
    assert_equal "z\n", out
  end
end
