# frozen_string_literal: true

require_relative 'test_helper'

class TestSHELLVariable < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_shell_test')
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # find_rubish_path tests

  def test_find_rubish_path_finds_bin_rubish
    repl = Rubish::REPL.new
    result = repl.send(:find_rubish_path)

    # Should find the bin/rubish in the project
    assert_not_nil result
    assert result.end_with?('rubish'), "Expected path ending with 'rubish', got: #{result}"
    assert File.executable?(result), "Expected executable file at: #{result}"
  end

  def test_find_rubish_path_searches_path
    # Create a fake rubish in tempdir
    fake_rubish = File.join(@tempdir, 'rubish')
    File.write(fake_rubish, "#!/bin/sh\necho rubish")
    File.chmod(0755, fake_rubish)

    # Add tempdir to PATH
    ENV['PATH'] = "#{@tempdir}:#{ENV['PATH']}"

    repl = Rubish::REPL.new
    result = repl.send(:find_rubish_path)

    assert_not_nil result
    assert result.end_with?('rubish')
  end

  # set_shell_variable tests

  def test_shell_variable_is_set_on_init
    # Clear SHELL first
    ENV.delete('SHELL')

    repl = Rubish::REPL.new

    # SHELL should be set after REPL initialization
    assert_not_nil ENV['SHELL']
    assert ENV['SHELL'].end_with?('rubish'), "Expected SHELL to end with 'rubish', got: #{ENV['SHELL']}"
  end

  def test_shell_variable_points_to_executable
    ENV.delete('SHELL')

    Rubish::REPL.new

    shell_path = ENV['SHELL']
    assert_not_nil shell_path
    assert File.executable?(shell_path), "SHELL should point to an executable: #{shell_path}"
  end

  def test_shell_variable_is_absolute_path
    ENV.delete('SHELL')

    Rubish::REPL.new

    shell_path = ENV['SHELL']
    assert_not_nil shell_path
    assert shell_path.start_with?('/'), "SHELL should be an absolute path: #{shell_path}"
  end

  # Integration tests

  def test_shell_variable_accessible_in_commands
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'shell_output.txt')

    repl.send(:execute, "echo $SHELL > #{output_file}")

    output = File.read(output_file).strip
    assert output.end_with?('rubish'), "Expected output ending with 'rubish', got: #{output}"
  end

  def test_shell_variable_inherited_by_subshell
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'subshell_output.txt')

    # Run in subshell
    repl.send(:execute, "(echo $SHELL) > #{output_file}")

    output = File.read(output_file).strip
    assert output.end_with?('rubish'), "Expected subshell SHELL ending with 'rubish', got: #{output}"
  end

  def test_shell_variable_passed_to_child_process
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'child_output.txt')

    # sh -c will inherit SHELL from environment
    repl.send(:execute, "sh -c 'echo $SHELL' > #{output_file}")

    output = File.read(output_file).strip
    assert output.end_with?('rubish'), "Expected child process SHELL ending with 'rubish', got: #{output}"
  end

  # Edge cases

  def test_shell_not_set_if_rubish_not_found
    # This is hard to test since we're running from the rubish project
    # But we can test that the method handles the nil case
    repl = Rubish::REPL.new

    # Temporarily break find_rubish_path
    def repl.find_rubish_path
      nil
    end

    # Clear and try to set again
    original_shell = ENV['SHELL']
    ENV.delete('SHELL')
    repl.send(:set_shell_variable)

    # SHELL should remain unset
    assert_nil ENV['SHELL']

    # Restore
    ENV['SHELL'] = original_shell
  end
end
