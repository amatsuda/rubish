# frozen_string_literal: true

require_relative 'test_helper'

# In an array literal, "${arr[@]}" contributes one element per element of
# arr, while "${arr[*]}" is a single joined element, as in bash
class TestArrayLiteralQuotedAt < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_quoted_at_expands_to_the_elements
    out = capture_stdout { execute('a=(a "b c" d); b=("${a[@]}" e); echo ${#b[@]} "${b[1]}" "${b[3]}"') }
    assert_equal "4 b c e\n", out
  end

  def test_quoted_star_is_one_element
    out = capture_stdout { execute('a=(a b); b=("${a[*]}" c); echo ${#b[@]} "${b[0]}"') }
    assert_equal "2 a b\n", out
  end

  def test_quoted_at_with_surrounding_text
    out = capture_stdout { execute('a=(x y); b=("<${a[@]}>"); echo ${#b[@]} "${b[0]}" "${b[1]}"') }
    assert_equal "2 <x y>\n", out
  end
end
