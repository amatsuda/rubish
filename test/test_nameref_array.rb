# frozen_string_literal: true

require_relative 'test_helper'

# A nameref to an array behaves like the array: elements, count and keys
class TestNamerefArray < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_elements_and_count_through_the_reference
    execute('arr_nr=(a b); declare -n ar_nr=arr_nr')
    out = capture_stdout { execute('echo "${ar_nr[1]} ${#ar_nr[@]} ${ar_nr[@]} ${!ar_nr[@]}"') }
    assert_equal "b 2 a b 0 1\n", out
  end

  def test_assignment_through_the_reference
    execute('arr_nr2=(a); declare -n ar_nr2=arr_nr2; ar_nr2[1]=z')
    out = capture_stdout { execute('echo "${arr_nr2[@]}"') }
    assert_equal "a z\n", out
  end
end
