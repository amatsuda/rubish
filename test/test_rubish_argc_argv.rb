# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_ARGC_ARGV < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_argc_argv_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic RUBISH_ARGC functionality

  def test_rubish_argc_empty_outside_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${RUBISH_ARGC[@]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value, 'RUBISH_ARGC should be empty outside functions'
  end

  def test_rubish_argc_contains_arg_count_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${RUBISH_ARGC[0]} > #{output_file}; }")
    execute('myfunc a b c')
    value = File.read(output_file).strip.to_i
    assert_equal 3, value
  end

  def test_rubish_argc_length_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${#RUBISH_ARGC[@]} > #{output_file}; }")
    execute('myfunc a b')
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_rubish_argc_zero_args
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${RUBISH_ARGC[0]} > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip.to_i
    assert_equal 0, value
  end

  def test_rubish_argc_nested_functions
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${RUBISH_ARGC[@]} > #{output_file}; }")
    execute('outer() { inner x y; }')
    execute('outer a b c')
    value = File.read(output_file).strip
    # inner was called with 2 args, outer was called with 3 args
    assert_equal '2 3', value
  end

  def test_rubish_argc_index_access_nested
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${RUBISH_ARGC[0]} ${RUBISH_ARGC[1]} > #{output_file}; }")
    execute('outer() { inner x y z; }')
    execute('outer a')
    value = File.read(output_file).strip
    # RUBISH_ARGC[0] = 3 (inner's args), RUBISH_ARGC[1] = 1 (outer's args)
    assert_equal '3 1', value
  end

  def test_rubish_argc_length_nested
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${#RUBISH_ARGC[@]} > #{output_file}; }")
    execute('outer() { inner x; }')
    execute('outer a b')
    value = File.read(output_file).strip.to_i
    assert_equal 2, value
  end

  # Basic RUBISH_ARGV functionality

  def test_rubish_argv_empty_outside_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${RUBISH_ARGV[@]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value, 'RUBISH_ARGV should be empty outside functions'
  end

  def test_rubish_argv_contains_args_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${RUBISH_ARGV[@]} > #{output_file}; }")
    execute('myfunc a b c')
    value = File.read(output_file).strip
    # Args are stored in reverse order within frame
    assert_equal 'c b a', value
  end

  def test_rubish_argv_length_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${#RUBISH_ARGV[@]} > #{output_file}; }")
    execute('myfunc a b c')
    value = File.read(output_file).strip.to_i
    assert_equal 3, value
  end

  def test_rubish_argv_zero_args
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo \"x${RUBISH_ARGV[@]}x\" > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_rubish_argv_nested_functions
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${RUBISH_ARGV[@]} > #{output_file}; }")
    execute('outer() { inner x y; }')
    execute('outer a b c')
    value = File.read(output_file).strip
    # inner's args (y x) then outer's args (c b a) - all reversed within their frames
    assert_equal 'y x c b a', value
  end

  def test_rubish_argv_index_access
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${RUBISH_ARGV[0]} ${RUBISH_ARGV[1]} ${RUBISH_ARGV[2]} > #{output_file}; }")
    execute('myfunc a b c')
    value = File.read(output_file).strip
    # RUBISH_ARGV[0] = c, RUBISH_ARGV[1] = b, RUBISH_ARGV[2] = a (reversed)
    assert_equal 'c b a', value
  end

  def test_rubish_argv_index_access_nested
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${RUBISH_ARGV[0]} ${RUBISH_ARGV[1]} ${RUBISH_ARGV[2]} ${RUBISH_ARGV[3]} > #{output_file}; }")
    execute('outer() { inner x y; }')
    execute('outer a b')
    value = File.read(output_file).strip
    # RUBISH_ARGV: [y, x, b, a] - inner's reversed, then outer's reversed
    assert_equal 'y x b a', value
  end

  # Stack behavior

  def test_rubish_argc_pops_on_return
    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("inner() { echo ${#RUBISH_ARGC[@]} > #{output_file1}; }")
    execute("outer() { inner x; echo ${#RUBISH_ARGC[@]} > #{output_file2}; }")
    execute('outer a b')
    inner_count = File.read(output_file1).strip.to_i
    outer_count = File.read(output_file2).strip.to_i
    assert_equal 2, inner_count
    assert_equal 1, outer_count
  end

  def test_rubish_argv_pops_on_return
    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("inner() { echo ${#RUBISH_ARGV[@]} > #{output_file1}; }")
    execute("outer() { inner x; echo ${#RUBISH_ARGV[@]} > #{output_file2}; }")
    execute('outer a b')
    inner_count = File.read(output_file1).strip.to_i
    outer_count = File.read(output_file2).strip.to_i
    assert_equal 3, inner_count  # 1 from inner + 2 from outer
    assert_equal 2, outer_count  # just outer's 2 args
  end

  def test_rubish_argc_empty_after_function_returns
    output_file = File.join(@tempdir, 'output.txt')
    execute('myfunc() { true; }')
    execute('myfunc a b c')
    execute("echo ${#RUBISH_ARGC[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 0, value
  end

  def test_rubish_argv_empty_after_function_returns
    output_file = File.join(@tempdir, 'output.txt')
    execute('myfunc() { true; }')
    execute('myfunc a b c')
    execute("echo ${#RUBISH_ARGV[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 0, value
  end

  # Keys

  def test_rubish_argc_keys_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${!RUBISH_ARGC[@]} > #{output_file}; }")
    execute('outer() { inner x; }')
    execute('outer a b')
    value = File.read(output_file).strip
    assert_equal '0 1', value
  end

  def test_rubish_argv_keys_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${!RUBISH_ARGV[@]} > #{output_file}; }")
    execute('myfunc a b c')
    value = File.read(output_file).strip
    assert_equal '0 1 2', value
  end

  # Read-only behavior

  def test_rubish_argc_assignment_ignored
    execute('RUBISH_ARGC=custom')
    argc_stack = @repl.instance_variable_get(:@rubish_argc_stack)
    assert_equal [], argc_stack
  end

  def test_rubish_argv_assignment_ignored
    execute('RUBISH_ARGV=custom')
    argv_stack = @repl.instance_variable_get(:@rubish_argv_stack)
    assert_equal [], argv_stack
  end

  def test_rubish_argc_not_stored_in_env
    assert_nil ENV['RUBISH_ARGC'], 'RUBISH_ARGC should not be stored in ENV'
    execute('myfunc() { echo $RUBISH_ARGC; }')
    execute('myfunc a b')
    assert_nil ENV['RUBISH_ARGC'], 'RUBISH_ARGC should still not be in ENV'
  end

  def test_rubish_argv_not_stored_in_env
    assert_nil ENV['RUBISH_ARGV'], 'RUBISH_ARGV should not be stored in ENV'
    execute('myfunc() { echo $RUBISH_ARGV; }')
    execute('myfunc a b')
    assert_nil ENV['RUBISH_ARGV'], 'RUBISH_ARGV should still not be in ENV'
  end

  # Edge cases

  def test_rubish_argc_out_of_bounds
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo \"x${RUBISH_ARGC[99]}x\" > #{output_file}; }")
    execute('myfunc a b')
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_rubish_argv_out_of_bounds
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo \"x${RUBISH_ARGV[99]}x\" > #{output_file}; }")
    execute('myfunc a b')
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_rubish_argc_negative_index
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${RUBISH_ARGC[-1]} > #{output_file}; }")
    execute('outer() { inner x y; }')
    execute('outer a')
    value = File.read(output_file).strip.to_i
    # Last element should be outer's argc (1)
    assert_equal 1, value
  end

  def test_rubish_argv_negative_index
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${RUBISH_ARGV[-1]} > #{output_file}; }")
    execute('myfunc a b c')
    value = File.read(output_file).strip
    # Last element should be 'a' (first arg, stored at end after reversal)
    assert_equal 'a', value
  end

  def test_rubish_argc_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    stack1 = repl1.instance_variable_get(:@rubish_argc_stack)
    stack2 = repl2.instance_variable_get(:@rubish_argc_stack)

    assert_equal [], stack1
    assert_equal [], stack2
    assert_not_same stack1, stack2
  end

  def test_rubish_argv_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    stack1 = repl1.instance_variable_get(:@rubish_argv_stack)
    stack2 = repl2.instance_variable_get(:@rubish_argv_stack)

    assert_equal [], stack1
    assert_equal [], stack2
    assert_not_same stack1, stack2
  end

  def test_rubish_argc_star_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("inner() { echo ${RUBISH_ARGC[*]} > #{output_file}; }")
    execute('outer() { inner x y; }')
    execute('outer a b c')
    value = File.read(output_file).strip
    assert_equal '2 3', value
  end

  def test_rubish_argv_star_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo ${RUBISH_ARGV[*]} > #{output_file}; }")
    execute('myfunc a b c')
    value = File.read(output_file).strip
    # Same as @ expansion for these tests
    assert_equal 'c b a', value
  end

  def test_deeply_nested_functions
    output_file = File.join(@tempdir, 'output.txt')
    execute("level3() { echo ${RUBISH_ARGC[@]} > #{output_file}; }")
    execute('level2() { level3 z; }')
    execute('level1() { level2 x y; }')
    execute('level1 a b c')
    value = File.read(output_file).strip
    # level3 called with 1 arg, level2 with 2, level1 with 3
    assert_equal '1 2 3', value
  end

  def test_deeply_nested_argv
    output_file = File.join(@tempdir, 'output.txt')
    execute("level3() { echo ${RUBISH_ARGV[@]} > #{output_file}; }")
    execute('level2() { level3 z; }')
    execute('level1() { level2 x y; }')
    execute('level1 a b c')
    value = File.read(output_file).strip
    # level3's args (z), level2's args (y x), level1's args (c b a)
    assert_equal 'z y x c b a', value
  end
end
