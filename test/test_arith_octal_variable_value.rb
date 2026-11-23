# frozen_string_literal: true

require_relative 'test_helper'

# A variable whose value starts with 0 is octal in arithmetic, as in bash
class TestArithOctalVariableValue < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_leading_zero_value_is_octal
    out = capture_stdout { execute('x=010; echo $(( x )) $(( 10#$x )) $(( x + 1 ))') }
    assert_equal "8 10 9\n", out
  end
  
  def test_plain_values_are_decimal
    out = capture_stdout { execute('y=10; z=0; echo $(( y )) $(( z )) $(( y + z ))') }
    assert_equal "10 0 10\n", out
  end
end
