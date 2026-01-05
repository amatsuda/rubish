# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_SOURCE < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_source_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic RUBISH_SOURCE functionality

  def test_rubish_source_empty_outside_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${RUBISH_SOURCE[@]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value, 'RUBISH_SOURCE should be empty outside functions'
  end

  def test_rubish_source_contains_source_file
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${RUBISH_SOURCE[0]} > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip
    # Function defined interactively should have 'main' as source
    assert_equal 'main', value
  end

  def test_rubish_source_length_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${#RUBISH_SOURCE[@]} > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_rubish_source_all_elements_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${RUBISH_SOURCE[@]} > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip
    assert_equal 'main', value
  end

  # Nested functions

  def test_rubish_source_nested_functions_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${#RUBISH_SOURCE[@]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip.to_i
    assert_equal 2, value
  end

  def test_rubish_source_deeply_nested_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("level3() { echo ${#RUBISH_SOURCE[@]} > #{output_file}; }")
    execute('level2() { level3; }')
    execute('level1() { level2; }')
    execute('level1')
    value = File.read(output_file).strip.to_i
    assert_equal 3, value
  end

  def test_rubish_source_index_access_nested
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${RUBISH_SOURCE[0]} ${RUBISH_SOURCE[1]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip
    # Both should be 'main' since both are defined interactively
    assert_equal 'main main', value
  end

  # Stack behavior

  def test_rubish_source_pops_on_return
    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("inner() { echo ${#RUBISH_SOURCE[@]} > #{output_file1}; }")
    execute("outer() { inner; echo ${#RUBISH_SOURCE[@]} > #{output_file2}; }")
    execute('outer')
    inner_count = File.read(output_file1).strip.to_i
    outer_count = File.read(output_file2).strip.to_i
    assert_equal 2, inner_count
    assert_equal 1, outer_count
  end

  def test_rubish_source_empty_after_function_returns
    output_file = File.join(@tempdir, 'output.txt')
    execute('myfunc() { true; }')
    execute('myfunc')
    execute("echo ${#RUBISH_SOURCE[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 0, value
  end

  # Keys

  def test_rubish_source_keys_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${!RUBISH_SOURCE[@]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip
    assert_equal '0 1', value
  end

  # Read-only behavior

  def test_rubish_source_assignment_ignored
    execute('RUBISH_SOURCE=custom')
    source_stack = @repl.instance_variable_get(:@rubish_source_stack)
    assert_equal [], source_stack
  end

  def test_rubish_source_not_stored_in_env
    assert_nil ENV['RUBISH_SOURCE'], 'RUBISH_SOURCE should not be stored in ENV'
    execute('myfunc() { echo $RUBISH_SOURCE; }')
    execute('myfunc')
    assert_nil ENV['RUBISH_SOURCE'], 'RUBISH_SOURCE should still not be in ENV'
  end

  # Edge cases

  def test_rubish_source_out_of_bounds
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo \"x${RUBISH_SOURCE[99]}x\" > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_rubish_source_negative_index
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${RUBISH_SOURCE[-1]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip
    # Last element should be 'main' (the outer function's source)
    assert_equal 'main', value
  end

  def test_rubish_source_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    # Each REPL should have independent RUBISH_SOURCE stacks
    stack1 = repl1.instance_variable_get(:@rubish_source_stack)
    stack2 = repl2.instance_variable_get(:@rubish_source_stack)

    assert_equal [], stack1
    assert_equal [], stack2
    assert_not_same stack1, stack2
  end

  def test_rubish_source_recursive_function
    output_file = File.join(@tempdir, 'output.txt')
    # Three functions calling each other simulating recursion
    execute('level1() { level2; }')
    execute('level2() { level3; }')
    execute("level3() { echo ${#RUBISH_SOURCE[@]} > #{output_file}; }")
    execute('level1')
    value = File.read(output_file).strip.to_i
    # Should have 3 levels: level1 -> level2 -> level3
    assert_equal 3, value
  end

  def test_rubish_source_star_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${RUBISH_SOURCE[*]} > #{output_file}; }")
    execute('outer() { inner; }')
    execute('outer')
    value = File.read(output_file).strip
    assert_equal 'main main', value
  end

  # Test with sourced file

  def test_rubish_source_from_sourced_file
    # Create a script that defines a function
    script_file = File.join(@tempdir, 'funcs.sh')
    output_file = File.join(@tempdir, 'output.txt')
    File.write(script_file, "sourcefunc() { echo ${RUBISH_SOURCE[0]} > #{output_file}; }")

    execute("source #{script_file}")
    execute('sourcefunc')
    value = File.read(output_file).strip
    # Function defined in sourced file should have that file as source
    assert_equal script_file, value
  end

  def test_rubish_source_mixed_sources
    # Create a script that defines a function
    script_file = File.join(@tempdir, 'lib.sh')
    output_file = File.join(@tempdir, 'output.txt')
    File.write(script_file, "libfunc() { echo ${RUBISH_SOURCE[@]} > #{output_file}; }")

    # Source the file and define a wrapper function interactively
    execute("source #{script_file}")
    execute('wrapper() { libfunc; }')
    execute('wrapper')
    value = File.read(output_file).strip

    # libfunc was defined in script_file, wrapper was defined in main
    # RUBISH_SOURCE should be: libfunc's source, wrapper's source
    parts = value.split
    assert_equal 2, parts.length
    assert_equal script_file, parts[0]  # libfunc's source
    assert_equal 'main', parts[1]       # wrapper's source
  end
end
