# frozen_string_literal: true

require_relative 'test_helper'

# ${arr[@]:offset:length} on a sparse array selects by index, as bash does
class TestSparseArraySlice < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_offset_is_an_index
    out = capture_stdout { execute('arr=([3]=x [7]=y); echo ${arr[@]:3:1}; echo ${arr[@]:4}; echo "[${arr[@]:8}]"') }
    assert_equal "x\ny\n[]\n", out
  end

  def test_dense_arrays_are_unchanged
    out = capture_stdout { execute('a=(p q r s); echo ${a[@]:1:2} ${a[@]: -1} "${a[@]:0:1}"') }
    assert_equal "q r s p\n", out
  end
end
