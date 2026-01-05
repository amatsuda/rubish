# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_SUBSHELL < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_subshell_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic RUBISH_SUBSHELL functionality

  def test_rubish_subshell_zero_in_main_shell
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_SUBSHELL > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 0, value, 'RUBISH_SUBSHELL should be 0 in main shell'
  end

  def test_rubish_subshell_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_SUBSHELL} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 0, value
  end

  def test_rubish_subshell_one_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $RUBISH_SUBSHELL > #{output_file})")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value, 'RUBISH_SUBSHELL should be 1 in first subshell'
  end

  def test_rubish_subshell_two_in_nested_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("((echo $RUBISH_SUBSHELL > #{output_file}))")
    value = File.read(output_file).strip.to_i
    assert_equal 2, value, 'RUBISH_SUBSHELL should be 2 in nested subshell'
  end

  def test_rubish_subshell_three_in_deeply_nested
    output_file = File.join(@tempdir, 'output.txt')
    execute("(((echo $RUBISH_SUBSHELL > #{output_file})))")
    value = File.read(output_file).strip.to_i
    assert_equal 3, value, 'RUBISH_SUBSHELL should be 3 in deeply nested subshell'
  end

  def test_rubish_subshell_unchanged_after_subshell
    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')
    execute('(echo in_subshell > /dev/null)')
    execute("echo $RUBISH_SUBSHELL > #{output_file1}")
    execute('(echo in_subshell > /dev/null)')
    execute("echo $RUBISH_SUBSHELL > #{output_file2}")
    value1 = File.read(output_file1).strip.to_i
    value2 = File.read(output_file2).strip.to_i
    assert_equal 0, value1, 'RUBISH_SUBSHELL should remain 0 after subshell exits'
    assert_equal 0, value2, 'RUBISH_SUBSHELL should remain 0 after another subshell'
  end

  # Read-only behavior

  def test_rubish_subshell_assignment_ignored
    execute('RUBISH_SUBSHELL=99')
    subshell_level = @repl.instance_variable_get(:@subshell_level)
    assert_equal 0, subshell_level, 'RUBISH_SUBSHELL assignment should be ignored'
  end

  def test_rubish_subshell_not_stored_in_env
    assert_nil ENV['RUBISH_SUBSHELL'], 'RUBISH_SUBSHELL should not be stored in ENV'
    execute('echo $RUBISH_SUBSHELL')
    assert_nil ENV['RUBISH_SUBSHELL'], 'RUBISH_SUBSHELL should still not be in ENV after access'
  end

  # Parameter expansion

  def test_rubish_subshell_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_SUBSHELL:-default} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0', value, 'RUBISH_SUBSHELL is set, should not use default'
  end

  def test_rubish_subshell_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_SUBSHELL:+set} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'set', value, 'RUBISH_SUBSHELL should be considered set'
  end

  # In different contexts

  def test_rubish_subshell_in_command_substitution
    output_file = File.join(@tempdir, 'output.txt')
    # Command substitution runs via system shell, not through REPL
    # So RUBISH_SUBSHELL is not visible there (returns empty/0)
    execute("echo $(echo $RUBISH_SUBSHELL) > #{output_file}")
    value = File.read(output_file).strip
    # System shell doesn't know about RUBISH_SUBSHELL, so it's empty or 0
    assert(value == '' || value == '0', "Expected empty or 0, got #{value}")
  end

  def test_rubish_subshell_in_pipeline_subshell
    output_file = File.join(@tempdir, 'output.txt')
    # Each component of a pipeline runs in a subshell
    execute("(echo $RUBISH_SUBSHELL) | cat > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_rubish_subshell_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { echo $RUBISH_SUBSHELL > #{output_file}; }")
    execute('myfunc')
    value = File.read(output_file).strip.to_i
    # Functions run in the same shell, not a subshell
    assert_equal 0, value
  end

  def test_rubish_subshell_in_subshell_in_function
    output_file = File.join(@tempdir, 'output.txt')
    execute("myfunc() { (echo $RUBISH_SUBSHELL > #{output_file}); }")
    execute('myfunc')
    value = File.read(output_file).strip.to_i
    # Subshell inside function should have level 1
    assert_equal 1, value
  end

  def test_rubish_subshell_initial_value
    # Fresh REPL should have subshell_level = 0
    repl = Rubish::REPL.new
    subshell_level = repl.instance_variable_get(:@subshell_level)
    assert_equal 0, subshell_level
  end

  def test_rubish_subshell_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    level1 = repl1.instance_variable_get(:@subshell_level)
    level2 = repl2.instance_variable_get(:@subshell_level)

    assert_equal 0, level1
    assert_equal 0, level2
  end
end
