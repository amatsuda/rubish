# frozen_string_literal: true

require_relative 'test_helper'

class TestExpansionOddments < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  # "${!arr[*]}" joins the keys with the first character of IFS
  def test_keys_joined_by_ifs
    execute('arr_k=(a b c)')
    out = capture_stdout { execute('IFS=-; echo "${!arr_k[*]}"; unset IFS') }
    assert_equal "0-1-2\n", out
  end

  # ${arr[@]@K} lists subscripts and quoted values
  def test_transform_k_on_arrays
    execute('arr_t=(1 2); declare -A m_t=([k]=v)')
    out = capture_stdout { execute('echo "${arr_t[@]@K}" "${m_t[@]@K}"') }
    assert_equal %(0 "1" 1 "2" k "v" \n), out # bash ends an associative pair with a space
  end

  # ${var~~} toggles the case of every character, ${var~} of the first
  def test_case_toggle
    execute('up_t=AbC')
    out = capture_stdout { execute('echo "${up_t~~}" "${up_t~}"') }
    assert_equal "aBc abC\n", out
  end
end
