# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_ARGV0 < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_argv0_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic RUBISH_ARGV0 functionality

  def test_dollar_zero_default
    ENV.delete('RUBISH_ARGV0')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $0 > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'rubish', value
  end

  def test_rubish_argv0_overrides_dollar_zero
    ENV['RUBISH_ARGV0'] = 'custom_name'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $0 > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'custom_name', value
  end

  def test_rubish_argv0_empty_uses_default
    ENV['RUBISH_ARGV0'] = ''
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $0 > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'rubish', value
  end

  def test_rubish_argv0_can_be_changed
    ENV['RUBISH_ARGV0'] = 'first_name'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $0 > #{output_file}")
    value1 = File.read(output_file).strip
    assert_equal 'first_name', value1

    ENV['RUBISH_ARGV0'] = 'second_name'
    execute("echo $0 > #{output_file}")
    value2 = File.read(output_file).strip
    assert_equal 'second_name', value2
  end

  def test_rubish_argv0_with_path
    ENV['RUBISH_ARGV0'] = '/usr/local/bin/myscript'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $0 > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '/usr/local/bin/myscript', value
  end

  def test_rubish_argv0_with_spaces
    ENV['RUBISH_ARGV0'] = 'my script name'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"$0\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'my script name', value
  end

  def test_rubish_argv0_unset_restores_default
    ENV['RUBISH_ARGV0'] = 'custom'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $0 > #{output_file}")
    value1 = File.read(output_file).strip
    assert_equal 'custom', value1

    ENV.delete('RUBISH_ARGV0')
    execute("echo $0 > #{output_file}")
    value2 = File.read(output_file).strip
    assert_equal 'rubish', value2
  end

  def test_rubish_argv0_in_subshell
    ENV['RUBISH_ARGV0'] = 'parent_name'
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $0) > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'parent_name', value
  end

  def test_rubish_argv0_settable_via_shell
    ENV.delete('RUBISH_ARGV0')
    output_file = File.join(@tempdir, 'output.txt')

    # Set on one line, use on next (variable expansion happens at parse time)
    execute('RUBISH_ARGV0=from_shell')
    execute("echo $0 > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'from_shell', value
  end
end
