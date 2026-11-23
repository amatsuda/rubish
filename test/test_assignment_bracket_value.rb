# frozen_string_literal: true

require_relative 'test_helper'

# A quoted value with a bracket expression is a plain string to assign,
# not an array or glob: `re="[0-9]"`
class TestAssignmentBracketValue < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_double_quoted_bracket_value
    out = capture_stdout { execute('re="[0-9]"; echo "[$re]"') }
    assert_equal "[[0-9]]\n", out
  end

  def test_regex_in_a_variable_anchored_at_both_ends
    out = capture_stdout { execute("re='^[0-9]+$'; [[ 123 =~ $re ]]; echo $?; [[ 12a =~ $re ]]; echo $?") }
    assert_equal "0\n1\n", out
  end

  def test_several_assignments_with_bracket_values
    out = capture_stdout { execute('a="[x]" b="[y]"; echo "$a$b"') }
    assert_equal "[x][y]\n", out
  end
end
