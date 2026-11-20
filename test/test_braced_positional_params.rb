# frozen_string_literal: true

require_relative 'test_helper'

# ${0}, ${1}, ${10} are the positional parameters, in both expansion paths
class TestBracedPositionalParams < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @repl.script_name = 'myscript'
    execute('set -- a b c d e f g h i j')
  end

  def echo(expr, list: false)
    capture_stdout { execute("#{list ? 'true; ' : ''}echo \"#{expr}\"") }.chomp
  end

  def test_braced_first_parameter
    assert_equal 'a', echo('${1}')
    assert_equal 'a', echo('${1}', list: true)
  end

  def test_two_digit_parameter_needs_braces
    assert_equal 'j', echo('${10}')
    assert_equal 'j', echo('${10}', list: true)
    assert_equal 'a0', echo('$10')
  end

  def test_braced_zero_is_script_name
    assert_equal 'myscript', echo('${0}')
    assert_equal 'myscript', echo('${0}', list: true)
  end

  def test_braced_parameter_with_adjacent_text
    assert_equal 'xay', echo('x${1}y')
  end

  def test_unset_parameter_is_empty
    execute('set --')
    assert_equal '', echo('${1}')
  end
end
