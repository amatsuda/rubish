# frozen_string_literal: true

require_relative 'test_helper'

# declare -p prints indexed and associative arrays as compound assignments
class TestDeclarePArrays < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_indexed_array
    execute('arr_dp=(1 "two words")')
    out = capture_stdout { execute('declare -p arr_dp') }
    assert_equal %(declare -a arr_dp=([0]="1" [1]="two words")\n), out
  end

  def test_sparse_indexed_array_lists_only_set_elements
    execute('sp_dp=(a b c)')
    execute("unset 'sp_dp[1]'")
    out = capture_stdout { execute('declare -p sp_dp') }
    assert_equal %(declare -a sp_dp=([0]="a" [2]="c")\n), out
  end

  def test_associative_array
    execute('declare -A map_dp=([k]=v)')
    out = capture_stdout { execute('declare -p map_dp') }
    assert_equal %(declare -A map_dp=([k]="v" )\n), out
  end

  def test_readonly_array_shows_r
    execute('ro_dp=(x)')
    execute('readonly ro_dp')
    out = capture_stdout { execute('declare -p ro_dp') }
    assert_equal %(declare -ar ro_dp=([0]="x")\n), out
  end
end
