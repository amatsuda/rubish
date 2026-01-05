# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_EXECUTION_STRING < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_execution_string_test')
    Dir.chdir(@tempdir)
    @rubish_bin = File.expand_path('../bin/rubish', __dir__)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic -c functionality

  def test_c_option_executes_command
    output = `#{@rubish_bin} -c 'echo hello'`.strip
    assert_equal 'hello', output
  end

  def test_c_option_exit_status_success
    system("#{@rubish_bin} -c 'true'")
    assert_equal 0, $?.exitstatus
  end

  def test_c_option_exit_status_failure
    system("#{@rubish_bin} -c 'false'")
    assert_equal 1, $?.exitstatus
  end

  def test_c_option_multiple_commands
    output = `#{@rubish_bin} -c 'echo one; echo two'`.strip
    assert_equal "one\ntwo", output
  end

  # RUBISH_EXECUTION_STRING variable

  def test_rubish_execution_string_set
    output = `#{@rubish_bin} -c 'echo $RUBISH_EXECUTION_STRING'`.strip
    assert_equal 'echo $RUBISH_EXECUTION_STRING', output
  end

  def test_rubish_execution_string_with_complex_command
    cmd = 'echo hello; echo world'
    output = `#{@rubish_bin} -c '#{cmd}; echo "---"; echo $RUBISH_EXECUTION_STRING'`.strip
    lines = output.split("\n")
    assert_equal 'hello', lines[0]
    assert_equal 'world', lines[1]
    assert_equal '---', lines[2]
    assert_equal "#{cmd}; echo \"---\"; echo $RUBISH_EXECUTION_STRING", lines[3]
  end

  def test_rubish_execution_string_not_set_in_interactive
    # In non -c mode, RUBISH_EXECUTION_STRING should not be set
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'output.txt')
    repl.send(:execute, "echo \"x${RUBISH_EXECUTION_STRING}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  # Positional parameters with -c

  def test_c_option_with_script_name
    output = `#{@rubish_bin} -c 'echo $0' myscript`.strip
    assert_equal 'myscript', output
  end

  def test_c_option_with_positional_params
    output = `#{@rubish_bin} -c 'echo $1 $2' myscript arg1 arg2`.strip
    assert_equal 'arg1 arg2', output
  end

  def test_c_option_dollar_hash
    output = `#{@rubish_bin} -c 'echo $#' myscript a b c`.strip
    assert_equal '3', output
  end

  def test_c_option_dollar_at
    output = `#{@rubish_bin} -c 'echo $@' myscript one two three`.strip
    assert_equal 'one two three', output
  end

  # Edge cases

  def test_c_option_empty_command
    output = `#{@rubish_bin} -c ''`.strip
    assert_equal '', output
  end

  def test_c_option_with_quotes
    output = `#{@rubish_bin} -c 'echo "hello world"'`.strip
    assert_equal 'hello world', output
  end

  def test_c_option_with_variable_expansion
    ENV['TESTVAR'] = 'testvalue'
    output = `#{@rubish_bin} -c 'echo $TESTVAR'`.strip
    assert_equal 'testvalue', output
  end
end
