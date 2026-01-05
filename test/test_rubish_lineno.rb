# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_LINENO < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_lineno_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic RUBISH_LINENO functionality

  def test_rubish_lineno_empty_outside_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${RUBISH_LINENO[@]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value, 'RUBISH_LINENO should be empty outside functions'
  end

  def test_rubish_lineno_contains_caller_line
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${RUBISH_LINENO[0]} > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip.to_i
    # RUBISH_LINENO[0] should contain the line number where myfunc was called
    assert value >= 0, "Expected non-negative line number, got #{value}"
  end

  def test_rubish_lineno_length_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${#RUBISH_LINENO[@]} > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_rubish_lineno_all_elements_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${#RUBISH_LINENO[@]} > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  # Nested functions

  def test_rubish_lineno_nested_functions_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${#RUBISH_LINENO[@]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip.to_i
    assert_equal 2, value
  end

  def test_rubish_lineno_deeply_nested_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("level3() { echo ${#RUBISH_LINENO[@]} > #{output_file}; }")
    execute('level2() { level3; }')
    execute('level1() { level2; }')
    execute('level1')
    value = File.read(output_file).strip.to_i
    assert_equal 3, value
  end

  def test_rubish_lineno_index_access_nested
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${RUBISH_LINENO[0]} ${RUBISH_LINENO[1]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip
    # Should have two line numbers
    parts = value.split
    assert_equal 2, parts.length
  end

  # Stack behavior

  def test_rubish_lineno_pops_on_return
    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("inner() { echo ${#RUBISH_LINENO[@]} > #{output_file1}; }")
    execute("outer() { inner; echo ${#RUBISH_LINENO[@]} > #{output_file2}; }")
    execute('outer')
    inner_count = File.read(output_file1).strip.to_i
    outer_count = File.read(output_file2).strip.to_i
    assert_equal 2, inner_count
    assert_equal 1, outer_count
  end

  def test_rubish_lineno_empty_after_function_returns
    output_file = File.join(@tempdir, 'output.txt')
    execute('myfunc() { true; }')
    execute('myfunc')
    execute("echo ${#RUBISH_LINENO[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 0, value
  end

  # Keys

  def test_rubish_lineno_keys_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${!RUBISH_LINENO[@]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip
    assert_equal '0 1', value
  end

  # Read-only behavior

  def test_rubish_lineno_assignment_ignored
    execute('RUBISH_LINENO=custom')
    lineno_stack = @repl.instance_variable_get(:@rubish_lineno_stack)
    assert_equal [], lineno_stack
  end

  def test_rubish_lineno_not_stored_in_env
    assert_nil ENV['RUBISH_LINENO'], 'RUBISH_LINENO should not be stored in ENV'
    execute('myfunc() { echo $RUBISH_LINENO; }')
    execute('myfunc')
    assert_nil ENV['RUBISH_LINENO'], 'RUBISH_LINENO should still not be in ENV'
  end

  # Edge cases

  def test_rubish_lineno_out_of_bounds
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo \"x${RUBISH_LINENO[99]}x\" > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_rubish_lineno_negative_index
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${RUBISH_LINENO[-1]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip.to_i
    # Last element should be a valid line number
    assert value >= 0, "Expected non-negative line number, got #{value}"
  end

  def test_rubish_lineno_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    # Each REPL should have independent RUBISH_LINENO stacks
    stack1 = repl1.instance_variable_get(:@rubish_lineno_stack)
    stack2 = repl2.instance_variable_get(:@rubish_lineno_stack)

    assert_equal [], stack1
    assert_equal [], stack2
    assert_not_same stack1, stack2
  end

  def test_rubish_lineno_recursive_function
    output_file = File.join(@tempdir, 'output.txt')
    # Three functions calling each other simulating recursion
    execute('level1() { level2; }')
    execute('level2() { level3; }')
    execute("level3() { echo ${#RUBISH_LINENO[@]} > #{output_file}; }")
    execute('level1')
    value = File.read(output_file).strip.to_i
    # Should have 3 levels: level1 -> level2 -> level3
    assert_equal 3, value
  end

  def test_rubish_lineno_star_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${#RUBISH_LINENO[*]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip.to_i
    assert_equal 2, value
  end
end
