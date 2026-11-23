# frozen_string_literal: true

require_relative 'test_helper'

# The test builtin: parenthesised expressions, and status 2 with a message
# for a non-integer operand or too many arguments, as in bash
class TestTestBuiltinErrors < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_parenthesised_expression
    out = capture_stdout { execute('[ \( 1 -eq 1 \) ]; echo $?; [ \( 1 -eq 2 \) -o \( 3 -eq 3 \) ]; echo $?') }
    assert_equal "0\n0\n", out
  end

  def test_non_integer_operand
    err = capture_stderr { @out = capture_stdout { execute('[ 1 -eq a ]; echo $?') } }
    assert_equal "2\n", @out
    assert_match(/integer expected/, err)
  end

  def test_too_many_arguments
    err = capture_stderr { @out = capture_stdout { execute("x='a b'; [ $x = 'a b' ]; echo $?") } }
    assert_equal "2\n", @out
    assert_match(/too many arguments/, err)
  end
end
