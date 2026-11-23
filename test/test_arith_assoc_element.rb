# frozen_string_literal: true

require_relative 'test_helper'

# An associative array element may be named directly in $(( ))
class TestArithAssocElement < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_associative_array_element
    out = capture_stdout { execute('declare -A m=([x]=7 [yz]=2); echo $(( m[x] + 1 )) $(( ${m[x]} )) $(( m[yz] * 2 ))') }
    assert_equal "8 7 4\n", out
  end
end
