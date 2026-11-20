# frozen_string_literal: true

require_relative 'test_helper'

# A builtin that is the whole command takes the REPL's in-process path, whose
# expansion must support the same ${...} operators as generated code
class TestFastPathParamExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    execute('x=abc.txt')
    execute('ref=x')
  end

  def teardown
    Rubish::Builtins.unset(%w[x ref])
  end

  # A lone `echo "..."` is dispatched directly to the builtin
  def echo(expansion)
    capture_stdout { execute("echo \"#{expansion}\"") }.chomp
  end

  def test_replace_first_and_all
    assert_equal 'aBc.txt', echo('${x/b/B}')
    assert_equal '__c.txt', echo('${x//[ab]/_}')
  end

  def test_delete_pattern
    assert_equal 'ac.txt', echo('${x/b}')
    assert_equal 'abc', echo('${x//.txt}')
  end

  def test_delete_pattern_in_generated_code
    out = capture_stdout { execute('true; echo "${x//.txt}"') }.chomp
    assert_equal 'abc', out
  end

  def test_prefix_and_suffix_removal
    assert_equal 'bc.txt', echo('${x#a}')
    assert_equal 'txt', echo('${x##*.}')
    assert_equal 'abc', echo('${x%.*}')
    assert_equal 'abc', echo('${x%%.*}')
  end

  def test_case_modification
    assert_equal 'Abc.txt', echo('${x^}')
    assert_equal 'ABC.TXT', echo('${x^^}')
    execute('y=ABC')
    assert_equal 'aBC', echo('${y,}')
    assert_equal 'abc', echo('${y,,}')
  ensure
    Rubish::Builtins.unset(['y'])
  end

  def test_transformations
    assert_equal 'ABC.TXT', echo('${x@U}')
    assert_equal "'abc.txt'", echo('${x@Q}')
  end

  def test_indirection
    assert_equal 'abc.txt', echo('${!ref}')
  end

  def test_same_results_as_generated_code
    fast = echo('${x/b/B}-${x##*.}-${x^^}')
    gen = capture_stdout { execute('true; echo "${x/b/B}-${x##*.}-${x^^}"') }.chomp
    assert_equal gen, fast
  end
end
