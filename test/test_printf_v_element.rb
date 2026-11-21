# frozen_string_literal: true

require_relative 'test_helper'

# printf -v can target an array element
class TestPrintfVElement < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_indexed_element
    execute("arr_pv=(x); printf -v 'arr_pv[1]' '%s' y")
    out = capture_stdout { execute('echo "${arr_pv[@]}"') }
    assert_equal "x y\n", out
  end

  def test_associative_element
    execute("declare -A m_pv; printf -v 'm_pv[k]' '%03d' 7")
    out = capture_stdout { execute('echo "${m_pv[k]}"') }
    assert_equal "007\n", out
  end
end
