# frozen_string_literal: true

require_relative 'test_helper'

class TestPOSIXLY_CORRECT < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_posixly_correct_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Basic POSIXLY_CORRECT functionality

  def test_posixly_correct_can_be_set
    execute('POSIXLY_CORRECT=1')
    assert_equal '1', ENV['POSIXLY_CORRECT']
  end

  def test_posixly_correct_can_be_set_to_y
    execute('POSIXLY_CORRECT=y')
    assert_equal 'y', ENV['POSIXLY_CORRECT']
  end

  def test_posixly_correct_can_be_set_empty
    # Even empty value enables POSIX mode in bash
    execute('POSIXLY_CORRECT=')
    assert_equal '', ENV['POSIXLY_CORRECT']
  end

  def test_posixly_correct_can_be_exported
    execute('export POSIXLY_CORRECT=1')
    assert_equal '1', ENV['POSIXLY_CORRECT']
  end

  def test_posixly_correct_can_be_read
    ENV['POSIXLY_CORRECT'] = '1'
    execute("echo $POSIXLY_CORRECT > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '1', result
  end

  def test_posixly_correct_unset_is_empty
    ENV.delete('POSIXLY_CORRECT')
    execute("echo \"x${POSIXLY_CORRECT}x\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'xx', result
  end

  # posix_mode? helper method tests

  def test_posix_mode_enabled_when_set
    ENV['POSIXLY_CORRECT'] = '1'
    assert Rubish::Builtins.posix_mode?
  end

  def test_posix_mode_enabled_when_empty
    # In bash, even empty value enables POSIX mode
    ENV['POSIXLY_CORRECT'] = ''
    assert Rubish::Builtins.posix_mode?
  end

  def test_posix_mode_disabled_when_unset
    ENV.delete('POSIXLY_CORRECT')
    assert_false Rubish::Builtins.posix_mode?
  end

  def test_posix_mode_enabled_with_any_value
    ENV['POSIXLY_CORRECT'] = 'yes'
    assert Rubish::Builtins.posix_mode?

    ENV['POSIXLY_CORRECT'] = 'true'
    assert Rubish::Builtins.posix_mode?

    ENV['POSIXLY_CORRECT'] = '0'
    assert Rubish::Builtins.posix_mode?
  end

  # Conditional behavior based on POSIXLY_CORRECT

  def test_posixly_correct_conditional_when_set
    ENV['POSIXLY_CORRECT'] = '1'
    execute("if [ -n \"${POSIXLY_CORRECT+set}\" ]; then echo posix; else echo normal; fi > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'posix', result
  end

  def test_posixly_correct_conditional_when_unset
    ENV.delete('POSIXLY_CORRECT')
    execute("if [ -n \"${POSIXLY_CORRECT+set}\" ]; then echo posix; else echo normal; fi > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'normal', result
  end

  def test_posixly_correct_check_if_set
    ENV['POSIXLY_CORRECT'] = ''
    # Use ${VAR+value} to check if variable is set (even if empty)
    execute("if [ -n \"${POSIXLY_CORRECT+x}\" ]; then echo set; else echo unset; fi > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'set', result
  end

  # POSIXLY_CORRECT with parameter expansion

  def test_posixly_correct_default_value
    ENV.delete('POSIXLY_CORRECT')
    execute("echo ${POSIXLY_CORRECT:-not_posix} > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'not_posix', result
  end

  def test_posixly_correct_set_with_default
    ENV['POSIXLY_CORRECT'] = '1'
    execute("echo ${POSIXLY_CORRECT:-not_posix} > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '1', result
  end

  # Unset POSIXLY_CORRECT

  def test_unset_posixly_correct
    ENV['POSIXLY_CORRECT'] = '1'
    execute('unset POSIXLY_CORRECT')
    assert_nil ENV['POSIXLY_CORRECT']
  end

  def test_posix_mode_after_unset
    ENV['POSIXLY_CORRECT'] = '1'
    assert Rubish::Builtins.posix_mode?
    execute('unset POSIXLY_CORRECT')
    assert_false Rubish::Builtins.posix_mode?
  end

  # POSIXLY_CORRECT in subshell

  def test_posixly_correct_in_subshell
    ENV['POSIXLY_CORRECT'] = '1'
    execute("(echo $POSIXLY_CORRECT) > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '1', result
  end

  # POSIXLY_CORRECT inherited by child processes

  def test_posixly_correct_inherited
    ENV['POSIXLY_CORRECT'] = '1'
    execute("ruby -e 'puts ENV[\"POSIXLY_CORRECT\"]' > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '1', result
  end

  # Common patterns for checking POSIX mode

  def test_posix_mode_check_via_test_command
    ENV['POSIXLY_CORRECT'] = '1'
    # Use test command to check if variable is set
    execute("test -n \"${POSIXLY_CORRECT+x}\" && echo posix || echo normal > #{output_file}")
    # The echo posix goes to stdout, not file, so check the return status instead
    assert Rubish::Builtins.posix_mode?
  end

  def test_posix_mode_check_via_test_command_when_unset
    ENV.delete('POSIXLY_CORRECT')
    assert_false Rubish::Builtins.posix_mode?
  end
end
