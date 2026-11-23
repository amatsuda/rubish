# frozen_string_literal: true

require_relative 'test_helper'

# Parameter expansions inside $(( )) are expanded first, as text, then the
# expression is evaluated: `${#arr[@]}`, `${u:-0}`, `10#$x`, `$#`
class TestArithParameterExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_array_length
    out = capture_stdout { execute('arr=(1 2 3); echo $(( ${#arr[@]} * 2 ))') }
    assert_equal "6\n", out
  end

  def test_default_value
    out = capture_stdout { execute('unset u; echo $(( ${u:-7} + 1 ))') }
    assert_equal "8\n", out
  end

  def test_array_elements
    out = capture_stdout { execute('arr=(1 2 3); echo $(( ${arr[1]} + ${arr[2]} ))') }
    assert_equal "5\n", out
  end

  def test_variable_after_a_base_prefix
    out = capture_stdout { execute('x=010; echo $(( 10#$x ))') }
    assert_equal "10\n", out
  end

  def test_positional_count
    out = capture_stdout { execute('set -- a b; echo $(( $# + 1 ))') }
    assert_equal "3\n", out
  end
end
