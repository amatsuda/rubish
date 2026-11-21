# frozen_string_literal: true

require_relative 'test_helper'

# ${var@A} yields an assignment that recreates the variable: `x='a b'` for a
# plain variable, `declare -i n='3'` when it has attributes, and a compound
# assignment for arrays, as in bash
class TestParamTransformA < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def expand(word)
    capture_stdout { execute("echo \"#{word}\"") }.chomp
  end

  def test_plain_variable_is_a_simple_assignment
    execute("x='a b'")
    assert_equal "x='a b'", expand('${x@A}')
  end

  def test_variable_with_attributes_uses_declare
    execute('declare -i n_pta=3')
    assert_equal "declare -i n_pta='3'", expand('${n_pta@A}')
  end

  def test_indexed_array
    execute('a=(1 2)')
    assert_equal 'declare -a a=([0]="1" [1]="2")', expand('${a[@]@A}')
  end

  def test_associative_array
    execute('declare -A m=([k]=v)')
    assert_equal 'declare -A m=([k]="v" )', expand('${m[@]@A}')
  end
end
