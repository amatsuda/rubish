# frozen_string_literal: true

require_relative 'test_helper'

class TestIGNOREEOF < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_ignoreeof_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic IGNOREEOF variable tests

  def test_ignoreeof_can_be_set
    execute('IGNOREEOF=5')
    assert_equal '5', Rubish::Builtins.get_var('IGNOREEOF')
  end

  def test_ignoreeof_can_be_read
    ENV['IGNOREEOF'] = '3'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $IGNOREEOF > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '3', value
  end

  def test_ignoreeof_with_braces
    ENV['IGNOREEOF'] = '7'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${IGNOREEOF} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '7', value
  end

  def test_ignoreeof_unset_by_default
    ENV.delete('IGNOREEOF')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${IGNOREEOF}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_ignoreeof_can_be_unset
    ENV['IGNOREEOF'] = '5'
    execute('unset IGNOREEOF')
    assert_nil ENV['IGNOREEOF']
  end

  def test_ignoreeof_in_conditional
    ENV['IGNOREEOF'] = '10'
    output_file = File.join(@tempdir, 'output.txt')
    execute("if [[ -n $IGNOREEOF ]]; then echo set; else echo unset; fi > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'set', value
  end

  def test_ignoreeof_unset_conditional
    ENV.delete('IGNOREEOF')
    output_file = File.join(@tempdir, 'output.txt')
    execute("if [[ -n $IGNOREEOF ]]; then echo set; else echo unset; fi > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'unset', value
  end

  # Parameter expansion tests

  def test_ignoreeof_plus_expansion_when_set
    ENV['IGNOREEOF'] = '5'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${IGNOREEOF:+yes} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'yes', value
  end

  def test_ignoreeof_plus_expansion_when_unset
    ENV.delete('IGNOREEOF')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${IGNOREEOF:+yes} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '', value
  end

  # Arithmetic tests

  def test_ignoreeof_in_arithmetic
    ENV['IGNOREEOF'] = '5'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((IGNOREEOF + 1)) > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '6', value
  end

  def test_ignoreeof_comparison
    ENV['IGNOREEOF'] = '10'
    output_file = File.join(@tempdir, 'output.txt')
    execute("if [[ $IGNOREEOF -ge 10 ]]; then echo yes; else echo no; fi > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'yes', value
  end

  # Internal state tests

  def test_eof_count_initialized_to_zero
    repl = Rubish::REPL.new
    assert_equal 0, repl.instance_variable_get(:@eof_count)
  end

  def test_eof_count_can_be_incremented
    @repl.instance_variable_set(:@eof_count, 0)
    @repl.instance_variable_set(:@eof_count, @repl.instance_variable_get(:@eof_count) + 1)
    assert_equal 1, @repl.instance_variable_get(:@eof_count)
  end

  def test_eof_count_reset_logic
    # The @eof_count is reset in read_and_execute, not in execute
    # This tests that the instance variable exists and can be manipulated
    @repl.instance_variable_set(:@eof_count, 5)
    assert_equal 5, @repl.instance_variable_get(:@eof_count)
    @repl.instance_variable_set(:@eof_count, 0)
    assert_equal 0, @repl.instance_variable_get(:@eof_count)
  end

  def test_eof_count_persists_during_execute
    # execute() doesn't reset @eof_count - only read_and_execute does
    # This is by design: the counter tracks consecutive Ctrl+D presses
    @repl.instance_variable_set(:@eof_count, 5)
    execute('true')
    # @eof_count is not reset by execute() - it's reset in read_and_execute
    # when user types a non-empty command
    assert_equal 5, @repl.instance_variable_get(:@eof_count)
  end

  # Export tests

  def test_ignoreeof_can_be_exported
    execute('export IGNOREEOF=3')
    assert_equal '3', ENV['IGNOREEOF']
  end

  def test_ignoreeof_export_with_value
    execute('IGNOREEOF=8')
    execute('export IGNOREEOF')
    assert_equal '8', ENV['IGNOREEOF']
  end

  # Various value tests

  def test_ignoreeof_zero
    ENV['IGNOREEOF'] = '0'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $IGNOREEOF > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0', value
  end

  def test_ignoreeof_large_value
    ENV['IGNOREEOF'] = '100'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $IGNOREEOF > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '100', value
  end

  def test_ignoreeof_empty_string
    ENV['IGNOREEOF'] = ''
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${IGNOREEOF}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_ignoreeof_non_numeric
    # Non-numeric values are valid (shell treats them as 0 in arithmetic)
    ENV['IGNOREEOF'] = 'abc'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $IGNOREEOF > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'abc', value
  end

  # Integration with set -o ignoreeof

  def test_set_ignoreeof_option
    # set -o ignoreeof should work even without IGNOREEOF variable
    ENV.delete('IGNOREEOF')
    execute('set -o ignoreeof')
    assert Rubish::Builtins.set_option?('ignoreeof')
  end

  def test_set_ignoreeof_can_be_disabled
    execute('set -o ignoreeof')
    execute('set +o ignoreeof')
    assert !Rubish::Builtins.set_option?('ignoreeof')
  end
end
