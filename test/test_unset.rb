# frozen_string_literal: true

require_relative 'test_helper'

class TestUnset < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_unset_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test unset variable
  def test_unset_variable
    ENV['TESTVAR'] = 'value'
    assert_equal 'value', ENV['TESTVAR']

    Rubish::Builtins.run('unset', ['TESTVAR'])
    assert_nil ENV['TESTVAR']
  end

  # Test unset multiple variables
  def test_unset_multiple_variables
    ENV['VAR1'] = 'one'
    ENV['VAR2'] = 'two'
    ENV['VAR3'] = 'three'

    Rubish::Builtins.run('unset', ['VAR1', 'VAR2', 'VAR3'])
    assert_nil ENV['VAR1']
    assert_nil ENV['VAR2']
    assert_nil ENV['VAR3']
  end

  # Test unset with -v flag (explicit variable mode)
  def test_unset_v_flag
    ENV['TESTVAR'] = 'value'
    Rubish::Builtins.run('unset', ['-v', 'TESTVAR'])
    assert_nil ENV['TESTVAR']
  end

  # Test unset nonexistent variable (should not error)
  def test_unset_nonexistent
    result = Rubish::Builtins.run('unset', ['NONEXISTENT_VAR'])
    assert result
  end

  # Test unset no args shows usage
  def test_unset_no_args
    output = capture_output { Rubish::Builtins.run('unset', []) }
    assert_match(/usage/, output)
  end

  # Test unset only flags shows usage
  def test_unset_only_flags
    output = capture_output { Rubish::Builtins.run('unset', ['-v']) }
    assert_match(/usage/, output)
  end

  # Test unset function with -f flag
  def test_unset_function
    execute('myfunc() { echo hello; }')
    assert @repl.functions.key?('myfunc')

    Rubish::Builtins.run('unset', ['-f', 'myfunc'])
    assert_false @repl.functions.key?('myfunc')
  end

  # Test unset multiple functions
  def test_unset_multiple_functions
    execute('func1() { echo one; }')
    execute('func2() { echo two; }')
    assert @repl.functions.key?('func1')
    assert @repl.functions.key?('func2')

    Rubish::Builtins.run('unset', ['-f', 'func1', 'func2'])
    assert_false @repl.functions.key?('func1')
    assert_false @repl.functions.key?('func2')
  end

  # Test unset function via REPL
  def test_unset_function_via_repl
    execute('myfunc() { echo hello; }')
    execute("myfunc > #{output_file}")
    assert_equal "hello\n", File.read(output_file)

    execute('unset -f myfunc')
    # After unsetting, the function should not exist
    assert_false @repl.functions.key?('myfunc')
  end

  # Test unset variable via REPL
  def test_unset_variable_via_repl
    ENV['TESTVAR'] = 'testvalue'
    execute('unset TESTVAR')
    assert_nil ENV['TESTVAR']
  end

  # Test unset with mixed flags
  def test_unset_mixed_flags_f_wins
    # When both -f and -v are specified, -f takes precedence
    execute('myfunc() { echo hello; }')
    ENV['myfunc'] = 'value'

    Rubish::Builtins.run('unset', ['-fv', 'myfunc'])
    # Function should be removed, variable should still exist
    assert_false @repl.functions.key?('myfunc')
    assert_equal 'value', ENV['myfunc']

    ENV.delete('myfunc')
  end

  # Test unset doesn't affect other variables
  def test_unset_isolation
    ENV['KEEP'] = 'keep_value'
    ENV['REMOVE'] = 'remove_value'

    Rubish::Builtins.run('unset', ['REMOVE'])
    assert_nil ENV['REMOVE']
    assert_equal 'keep_value', ENV['KEEP']

    ENV.delete('KEEP')
  end
end
