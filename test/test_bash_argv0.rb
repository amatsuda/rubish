# frozen_string_literal: true

require_relative 'test_helper'

class TestBashArgv0 < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_argv0_test')
  end

  def teardown
    ENV.replace(@original_env)
    FileUtils.rm_rf(@tempdir)
  end

  # Basic BASH_ARGV0 functionality

  def test_bash_argv0_returns_script_name
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_ARGV0 > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'rubish', value, 'BASH_ARGV0 should return the script name'
  end

  def test_bash_argv0_same_as_dollar_zero
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_ARGV0 $0 > #{output_file}")
    values = File.read(output_file).strip.split
    assert_equal 2, values.length
    assert_equal values[0], values[1], 'BASH_ARGV0 should equal $0'
  end

  def test_bash_argv0_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_ARGV0} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'rubish', value
  end

  def test_bash_argv0_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Name: $BASH_ARGV0\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'Name: rubish', content
  end

  # BASH_ARGV0 assignment sets $0

  def test_bash_argv0_assignment_sets_dollar_zero
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_ARGV0=myshell')
    execute("echo $0 > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'myshell', value, 'Assigning to BASH_ARGV0 should set $0'
  end

  def test_bash_argv0_assignment_and_read
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_ARGV0=customname')
    execute("echo $BASH_ARGV0 > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'customname', value
  end

  def test_bash_argv0_multiple_assignments
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_ARGV0=first')
    execute('BASH_ARGV0=second')
    execute('BASH_ARGV0=third')
    execute("echo $BASH_ARGV0 > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'third', value
  end

  # BASH_ARGV0 not stored in regular ENV

  def test_bash_argv0_not_stored_in_env_directly
    execute('BASH_ARGV0=testname')
    # BASH_ARGV0 should not be in ENV as a regular variable
    # It stores via RUBISH_ARGV0
    assert_nil ENV['BASH_ARGV0'], 'BASH_ARGV0 should not be stored directly in ENV'
    assert_equal 'testname', ENV['RUBISH_ARGV0'], 'RUBISH_ARGV0 should store the value'
  end

  # BASH_ARGV0 loses special properties when unset

  def test_bash_argv0_loses_properties_when_unset
    # First, set BASH_ARGV0
    execute('BASH_ARGV0=testvalue')
    output_file = File.join(@tempdir, 'output1.txt')
    execute("echo $BASH_ARGV0 > #{output_file}")
    value1 = File.read(output_file).strip
    assert_equal 'testvalue', value1

    # Unset BASH_ARGV0
    execute('unset BASH_ARGV0')

    # After unset, BASH_ARGV0 should be empty (lost special properties)
    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("echo \"$BASH_ARGV0\" > #{output_file2}")
    value2 = File.read(output_file2).strip
    assert_equal '', value2, 'BASH_ARGV0 should be empty after unset'
  end

  def test_bash_argv0_unset_then_assign_no_effect_on_dollar_zero
    # Set a known value
    execute('BASH_ARGV0=original')
    output_file1 = File.join(@tempdir, 'output1.txt')
    execute("echo $0 > #{output_file1}")
    value1 = File.read(output_file1).strip
    assert_equal 'original', value1

    # Unset BASH_ARGV0
    execute('unset BASH_ARGV0')

    # Now assign again - should NOT affect $0 (lost special properties)
    execute('BASH_ARGV0=newvalue')

    # $0 should still be 'original' (from RUBISH_ARGV0)
    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("echo $0 > #{output_file2}")
    value2 = File.read(output_file2).strip
    # After unset, assignment goes to regular ENV, not RUBISH_ARGV0
    # So $0 stays at 'original'
    assert_equal 'original', value2, '$0 should not change after BASH_ARGV0 loses special properties'

    # But BASH_ARGV0 itself should now be a regular variable
    output_file3 = File.join(@tempdir, 'output3.txt')
    execute("echo $BASH_ARGV0 > #{output_file3}")
    value3 = File.read(output_file3).strip
    assert_equal 'newvalue', value3, 'BASH_ARGV0 should be a regular variable after unset'
  end

  # Parameter expansion

  def test_bash_argv0_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_ARGV0:-default} > #{output_file}")
    value = File.read(output_file).strip
    # Should return the actual value, not default
    assert_equal 'rubish', value
  end

  def test_bash_argv0_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_ARGV0:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'BASH_ARGV0 should be considered set'
  end

  # Edge cases

  def test_bash_argv0_empty_assignment
    execute('BASH_ARGV0=')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"$BASH_ARGV0\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '', value
  end

  def test_bash_argv0_assignment_with_special_chars
    execute('BASH_ARGV0=/usr/local/bin/my-shell')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_ARGV0 > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '/usr/local/bin/my-shell', value
  end

  def test_bash_argv0_assignment_with_spaces_quoted
    execute('BASH_ARGV0="my shell name"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"$BASH_ARGV0\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'my shell name', value
  end

  # Integration with $0

  def test_bash_argv0_synchronizes_with_dollar_zero
    output_file = File.join(@tempdir, 'output.txt')

    # Initial values should match
    execute("echo $BASH_ARGV0 $0 > #{output_file}")
    values = File.read(output_file).strip.split
    assert_equal values[0], values[1]

    # After assignment to BASH_ARGV0, $0 should also change
    execute('BASH_ARGV0=newname')
    execute("echo $BASH_ARGV0 $0 >> #{output_file}")
    content = File.read(output_file).strip.split("\n")
    values2 = content[1].split
    assert_equal 'newname', values2[0]
    assert_equal 'newname', values2[1]
  end

  # argv0 method

  def test_bash_argv0_method_returns_string
    value = @repl.send(:argv0)
    assert_kind_of String, value
    assert_equal 'rubish', value
  end

  def test_bash_argv0_method_respects_rubish_argv0
    ENV['RUBISH_ARGV0'] = 'custom_shell'
    value = @repl.send(:argv0)
    assert_equal 'custom_shell', value
  end
end
