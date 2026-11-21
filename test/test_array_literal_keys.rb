# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Compound assignments may give each element its subscript: `a=([2]=x [0]=y)`
# for indexed arrays and `m=([k]=v)` for associative ones, also with `+=`
class TestArrayLiteralKeys < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_arr') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_associative_literal_with_keys
    execute('declare -A m')
    execute('m=([k]=v [j]=w)')
    assert_equal "v w 2\n", run_and_read('echo "${m[k]} ${m[j]} ${#m[@]}"')
  end

  def test_associative_append
    execute('declare -A m')
    execute('m=([a]=1)')
    execute('m+=([b]=2)')
    assert_equal "1 2 2\n", run_and_read('echo "${m[a]} ${m[b]} ${#m[@]}"')
  end

  def test_indexed_literal_with_explicit_indices
    execute('a=([2]=x [0]=y)')
    assert_equal "x y 2 0 2\n", run_and_read('echo "${a[2]} ${a[0]} ${#a[@]} ${!a[@]}"')
  end

  def test_unindexed_element_follows_the_previous_index
    execute('a=([1]=x y [5]=z w)')
    assert_equal "x y z w\n", run_and_read('echo "${a[1]} ${a[2]} ${a[5]} ${a[6]}"')
  end

  def test_indexed_append_with_index
    execute('a=(p q)')
    execute('a+=([5]=z)')
    assert_equal "z 3\n", run_and_read('echo "${a[5]} ${#a[@]}"')
  end

  def test_keys_and_values_are_expanded
    execute('k=key; v="two words"')
    execute('declare -A m')
    execute('m=([$k]="$v")')
    assert_equal "two words\n", run_and_read('echo "${m[key]}"')
  end

  def test_associative_literal_inside_a_command_list
    assert_equal "v 1\n", run_and_read('declare -A n; n=([k]=v); echo "${n[k]} ${#n[@]}"')
  end

  def test_indexed_literal_inside_a_command_list
    assert_equal "x 2\n", run_and_read('b=([3]=x [1]=y); echo "${b[3]} ${#b[@]}"')
  end

  def test_plain_elements_still_work
    execute('a=(one two)')
    assert_equal "one two 2\n", run_and_read('echo "${a[@]} ${#a[@]}"')
  end
end
