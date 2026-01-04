# frozen_string_literal: true

require_relative 'test_helper'

class TestArray < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_array_test')
    @saved_env = ENV.to_h
    Rubish::Builtins.instance_variable_set(:@arrays, {})
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @saved_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.instance_variable_set(:@arrays, {})
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Array declaration
  def test_array_declaration
    execute('arr=(a b c)')
    assert_equal %w[a b c], Rubish::Builtins.get_array('arr')
  end

  def test_array_declaration_empty
    execute('arr=()')
    assert_equal [], Rubish::Builtins.get_array('arr')
  end

  def test_array_declaration_with_quotes
    execute("arr=('hello world' foo 'bar baz')")
    assert_equal ['hello world', 'foo', 'bar baz'], Rubish::Builtins.get_array('arr')
  end

  def test_array_declaration_with_variables
    ENV['X'] = 'expanded'
    execute('arr=(a $X c)')
    assert_equal %w[a expanded c], Rubish::Builtins.get_array('arr')
  end

  # Array element access
  def test_array_element_access
    execute('arr=(one two three)')
    execute("echo ${arr[0]} > #{output_file}")
    assert_equal "one\n", File.read(output_file)
  end

  def test_array_element_access_second
    execute('arr=(one two three)')
    execute("echo ${arr[1]} > #{output_file}")
    assert_equal "two\n", File.read(output_file)
  end

  def test_array_element_access_last
    execute('arr=(one two three)')
    execute("echo ${arr[2]} > #{output_file}")
    assert_equal "three\n", File.read(output_file)
  end

  def test_array_element_out_of_bounds
    execute('arr=(one two)')
    execute("echo ${arr[5]} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  # Array element assignment
  def test_array_element_assignment
    execute('arr=(a b c)')
    execute('arr[1]=modified')
    assert_equal %w[a modified c], Rubish::Builtins.get_array('arr')
  end

  def test_array_element_assignment_extend
    execute('arr=(a b)')
    execute('arr[5]=far')
    arr = Rubish::Builtins.get_array('arr')
    assert_equal 'a', arr[0]
    assert_equal 'b', arr[1]
    assert_equal 'far', arr[5]
  end

  def test_array_element_assignment_new_array
    execute('newarr[0]=first')
    assert_equal 'first', Rubish::Builtins.get_array_element('newarr', 0)
  end

  # Array append
  def test_array_append
    execute('arr=(a b)')
    execute('arr+=(c d)')
    assert_equal %w[a b c d], Rubish::Builtins.get_array('arr')
  end

  def test_array_append_to_empty
    execute('arr=()')
    execute('arr+=(x y)')
    assert_equal %w[x y], Rubish::Builtins.get_array('arr')
  end

  # All elements
  def test_array_all_at
    execute('arr=(one two three)')
    execute("echo ${arr[@]} > #{output_file}")
    assert_equal "one two three\n", File.read(output_file)
  end

  def test_array_all_star
    execute('arr=(one two three)')
    execute("echo ${arr[*]} > #{output_file}")
    assert_equal "one two three\n", File.read(output_file)
  end

  # Array length
  def test_array_length
    execute('arr=(a b c d e)')
    execute("echo ${#arr[@]} > #{output_file}")
    assert_equal "5\n", File.read(output_file)
  end

  def test_array_length_empty
    execute('arr=()')
    execute("echo ${#arr[@]} > #{output_file}")
    assert_equal "0\n", File.read(output_file)
  end

  def test_array_length_star
    execute('arr=(a b c)')
    execute("echo ${#arr[*]} > #{output_file}")
    assert_equal "3\n", File.read(output_file)
  end

  # Array in echo with multiple elements
  def test_array_echo_multiple
    execute('arr=(first second third)')
    execute("echo first=${arr[0]} second=${arr[1]} > #{output_file}")
    assert_equal "first=first second=second\n", File.read(output_file)
  end

  # Multiple arrays
  def test_multiple_arrays
    execute('a=(1 2 3)')
    execute('b=(x y z)')
    assert_equal %w[1 2 3], Rubish::Builtins.get_array('a')
    assert_equal %w[x y z], Rubish::Builtins.get_array('b')
  end

  # Array with arithmetic index
  def test_array_arithmetic_index
    execute('arr=(a b c d e)')
    ENV['i'] = '2'
    execute("echo ${arr[$i]} > #{output_file}")
    assert_equal "c\n", File.read(output_file)
  end

  # Builtins helper methods
  def test_array_predicate
    execute('arr=(a b c)')
    assert Rubish::Builtins.array?('arr')
    assert_false Rubish::Builtins.array?('nonexistent')
  end

  def test_unset_array
    execute('arr=(a b c)')
    Rubish::Builtins.unset_array('arr')
    assert_false Rubish::Builtins.array?('arr')
  end

  def test_unset_array_element
    execute('arr=(a b c)')
    Rubish::Builtins.unset_array_element('arr', 1)
    arr = Rubish::Builtins.get_array('arr')
    assert_equal 'a', arr[0]
    assert_nil arr[1]
    assert_equal 'c', arr[2]
  end
end
