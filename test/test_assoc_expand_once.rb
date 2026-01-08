# frozen_string_literal: true

require_relative 'test_helper'

class TestAssocExpandOnce < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_assoc_expand_once_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    # Clear any existing assoc arrays
    Rubish::Builtins.instance_variable_get(:@assoc_arrays).clear
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.instance_variable_get(:@assoc_arrays).clear
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # assoc_expand_once is disabled by default
  def test_assoc_expand_once_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('assoc_expand_once')
  end

  def test_assoc_expand_once_can_be_enabled
    execute('shopt -s assoc_expand_once')
    assert Rubish::Builtins.shopt_enabled?('assoc_expand_once')
  end

  def test_assoc_expand_once_can_be_disabled
    execute('shopt -s assoc_expand_once')
    execute('shopt -u assoc_expand_once')
    assert_false Rubish::Builtins.shopt_enabled?('assoc_expand_once')
  end

  # Test double expansion behavior when disabled (default)
  def test_double_expansion_when_disabled
    # Set up: actual_key='real_key', indirect='$actual_key', arr[real_key]=value
    execute('actual_key=real_key')
    execute('indirect=\'$actual_key\'')
    execute('declare -A arr')
    execute('arr[real_key]=found_value')

    # Without assoc_expand_once, $indirect -> '$actual_key' -> 'real_key'
    execute("echo ${arr[$indirect]} > #{output_file}")
    assert_equal "found_value\n", File.read(output_file)
  end

  # Test single expansion when enabled
  def test_single_expansion_when_enabled
    execute('shopt -s assoc_expand_once')

    # Set up: actual_key='real_key', indirect='$actual_key', arr[real_key]=value
    ENV['actual_key'] = 'real_key'
    ENV['indirect'] = '$actual_key'
    execute('declare -A arr')
    # Use API to set literal key since shell would expand it
    Rubish::Builtins.set_assoc_element('arr', 'real_key', 'found_value')
    Rubish::Builtins.set_assoc_element('arr', '$actual_key', 'literal_value')

    # With assoc_expand_once, $indirect -> '$actual_key' (used as literal key)
    execute("echo ${arr[$indirect]} > #{output_file}")
    assert_equal "literal_value\n", File.read(output_file)
  end

  # Test assignment with double expansion when disabled
  def test_assignment_double_expansion_when_disabled
    execute('keyvar=mykey')
    execute('indirection=\'$keyvar\'')
    execute('declare -A map')

    # Without assoc_expand_once, $indirection -> '$keyvar' -> 'mykey'
    execute('map[$indirection]=value1')

    # The value should be stored under 'mykey'
    val = Rubish::Builtins.get_assoc_element('map', 'mykey')
    assert_equal 'value1', val
  end

  # Test assignment with single expansion when enabled
  def test_assignment_single_expansion_when_enabled
    execute('shopt -s assoc_expand_once')

    execute('keyvar=mykey')
    execute('indirection=\'$keyvar\'')
    execute('declare -A map')

    # With assoc_expand_once, $indirection -> '$keyvar' (literal)
    execute('map[$indirection]=value1')

    # The value should be stored under '$keyvar' (literal)
    val = Rubish::Builtins.get_assoc_element('map', '$keyvar')
    assert_equal 'value1', val
  end

  # Test that indexed arrays are not affected
  def test_indexed_arrays_not_affected
    execute('key=5')
    execute('arr=(a b c d e f g)')

    # Indexed arrays don't use assoc_expand_once
    # The behavior should be the same regardless of the option
    execute("echo ${arr[$key]} > #{output_file}")
    output1 = File.read(output_file)

    execute('shopt -s assoc_expand_once')

    execute("echo ${arr[$key]} > #{output_file}")
    output2 = File.read(output_file)

    # Both should access arr[5] = 'f'
    assert_equal "f\n", output1
    assert_equal output1, output2
  end

  # Test with no variable in subscript (no expansion needed)
  def test_literal_subscript_not_affected
    execute('declare -A arr')
    execute('arr[literal]=value1')

    execute("echo ${arr[literal]} > #{output_file}")
    output1 = File.read(output_file)

    execute('shopt -s assoc_expand_once')

    execute("echo ${arr[literal]} > #{output_file}")
    output2 = File.read(output_file)

    assert_equal "value1\n", output1
    assert_equal output1, output2
  end

  # Test with simple variable (single expansion only)
  def test_simple_variable_same_behavior
    execute('mykey=thekey')
    execute('declare -A arr')
    execute('arr[thekey]=thevalue')

    execute("echo ${arr[$mykey]} > #{output_file}")
    output1 = File.read(output_file)

    execute('shopt -s assoc_expand_once')

    execute("echo ${arr[$mykey]} > #{output_file}")
    output2 = File.read(output_file)

    # Both should work the same since there's only one level of expansion
    assert_equal "thevalue\n", output1
    assert_equal output1, output2
  end

  # Test toggle behavior
  def test_toggle_assoc_expand_once
    ENV['actual'] = 'realkey'
    ENV['indirect'] = '$actual'
    execute('declare -A map')
    # Use API to set literal key since shell would expand it
    Rubish::Builtins.set_assoc_element('map', 'realkey', 'from_real')
    Rubish::Builtins.set_assoc_element('map', '$actual', 'from_literal')

    # Default: double expansion
    execute("echo ${map[$indirect]} > #{output_file}")
    output1 = File.read(output_file)
    assert_equal "from_real\n", output1

    # Enable: single expansion
    execute('shopt -s assoc_expand_once')
    execute("echo ${map[$indirect]} > #{output_file}")
    output2 = File.read(output_file)
    assert_equal "from_literal\n", output2

    # Disable: back to double expansion
    execute('shopt -u assoc_expand_once')
    execute("echo ${map[$indirect]} > #{output_file}")
    output3 = File.read(output_file)
    assert_equal "from_real\n", output3
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt assoc_expand_once')
    end
    assert_match(/assoc_expand_once/, output)
    assert_match(/off/, output)

    execute('shopt -s assoc_expand_once')

    output = capture_output do
      execute('shopt assoc_expand_once')
    end
    assert_match(/assoc_expand_once/, output)
    assert_match(/on/, output)
  end
end
