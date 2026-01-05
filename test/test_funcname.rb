# frozen_string_literal: true

require_relative 'test_helper'

class TestFUNCNAME < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_funcname_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic FUNCNAME functionality

  def test_funcname_empty_outside_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${FUNCNAME[@]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value, 'FUNCNAME should be empty outside functions'
  end

  def test_funcname_contains_current_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${FUNCNAME[0]} > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip
    assert_equal 'myfunc', value
  end

  def test_funcname_length_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${#FUNCNAME[@]} > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_funcname_all_elements_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${FUNCNAME[@]} > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip
    assert_equal 'myfunc', value
  end

  # Nested functions

  def test_funcname_nested_functions
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${FUNCNAME[@]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip
    assert_equal 'inner outer', value
  end

  def test_funcname_deeply_nested
    output_file = File.join(@tempdir, 'output.txt')
    execute("level3() { echo ${FUNCNAME[@]} > #{output_file}; }")
    execute('level2() { level3; }')
    execute('level1() { level2; }')
    execute('level1')
    value = File.read(output_file).strip
    assert_equal 'level3 level2 level1', value
  end

  def test_funcname_index_access_nested
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${FUNCNAME[0]} ${FUNCNAME[1]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip
    assert_equal 'inner outer', value
  end

  def test_funcname_length_nested
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${#FUNCNAME[@]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip.to_i
    assert_equal 2, value
  end

  # Stack behavior

  def test_funcname_pops_on_return
    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("inner() { echo ${#FUNCNAME[@]} > #{output_file1}; }")
    execute("outer() { inner; echo ${#FUNCNAME[@]} > #{output_file2}; }")
    execute('outer')
    inner_count = File.read(output_file1).strip.to_i
    outer_count = File.read(output_file2).strip.to_i
    assert_equal 2, inner_count
    assert_equal 1, outer_count
  end

  def test_funcname_empty_after_function_returns
    output_file = File.join(@tempdir, 'output.txt')
    execute('myfunc() { true; }')
    execute('myfunc')
    execute("echo ${#FUNCNAME[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 0, value
  end

  # Keys

  def test_funcname_keys_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${!FUNCNAME[@]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip
    assert_equal '0 1', value
  end

  # Read-only behavior

  def test_funcname_assignment_ignored
    execute('FUNCNAME=custom')
    funcname_stack = @repl.instance_variable_get(:@funcname_stack)
    assert_equal [], funcname_stack
  end

  def test_funcname_not_stored_in_env
    assert_nil ENV['FUNCNAME'], 'FUNCNAME should not be stored in ENV'
    execute('myfunc() { echo $FUNCNAME; }')
    execute('myfunc')
    assert_nil ENV['FUNCNAME'], 'FUNCNAME should still not be in ENV'
  end

  # Edge cases

  def test_funcname_out_of_bounds
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo \"x${FUNCNAME[99]}x\" > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_funcname_negative_index
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${FUNCNAME[-1]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip
    # Last element should be 'outer'
    assert_equal 'outer', value
  end

  def test_funcname_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    # Each REPL should have independent FUNCNAME stacks
    stack1 = repl1.instance_variable_get(:@funcname_stack)
    stack2 = repl2.instance_variable_get(:@funcname_stack)

    assert_equal [], stack1
    assert_equal [], stack2
    assert_not_same stack1, stack2
  end

  def test_funcname_recursive_function
    output_file = File.join(@tempdir, 'output.txt')
    # Three functions calling each other simulating recursion
    execute('level1() { level2; }')
    execute('level2() { level3; }')
    execute("level3() { echo ${#FUNCNAME[@]} > #{output_file}; }")
    execute('level1')
    value = File.read(output_file).strip.to_i
    # Should have 3 levels: level1 -> level2 -> level3
    assert_equal 3, value
  end

  def test_funcname_star_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${FUNCNAME[*]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip
    assert_equal 'inner outer', value
  end
end
