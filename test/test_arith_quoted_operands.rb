# frozen_string_literal: true

require_relative 'test_helper'

# Double quotes inside $(( )) are removed before evaluation, as bash does:
# $(( "1" + 1 )) is 2 and $(( "x" + 1 )) reads x
class TestArithQuotedOperands < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_double_quoted_number
    execute('r=$(( "1" + 1 ))')
    assert_equal '2', get_shell_var('r')
  end

  def test_double_quoted_variable_name
    execute('x=4; r=$(( "x" * 2 ))')
    assert_equal '8', get_shell_var('r')
  end

  def test_single_quotes_are_still_an_error
    err = capture_stderr { execute("r=$(( 'a' ))") }
    assert_match(/arithmetic|syntax error/, err)
  end
end
