# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_COMMAND < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_command_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic RUBISH_COMMAND functionality

  def test_rubish_command_contains_current_command
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_COMMAND > #{output_file}")
    value = File.read(output_file).strip
    # RUBISH_COMMAND should contain the command that was executed
    assert_match(/echo.*RUBISH_COMMAND/, value)
  end

  def test_rubish_command_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_COMMAND} > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/echo.*RUBISH_COMMAND/, value)
  end

  def test_rubish_command_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"cmd: $RUBISH_COMMAND\" > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/cmd:.*RUBISH_COMMAND/, content)
  end

  def test_rubish_command_updates_for_each_command
    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    execute("echo first $RUBISH_COMMAND > #{output_file1}")
    execute("echo second $RUBISH_COMMAND > #{output_file2}")

    value1 = File.read(output_file1).strip
    value2 = File.read(output_file2).strip

    assert_match(/first/, value1)
    assert_match(/second/, value2)
  end

  def test_rubish_command_with_simple_command
    output_file = File.join(@tempdir, 'output.txt')
    execute('true')
    execute("echo $RUBISH_COMMAND > #{output_file}")
    value = File.read(output_file).strip
    # After 'true', RUBISH_COMMAND should reflect the echo command
    assert_match(/echo.*RUBISH_COMMAND/, value)
  end

  # Read-only behavior

  def test_rubish_command_assignment_ignored
    execute('echo hello')
    execute('RUBISH_COMMAND=custom')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_COMMAND > #{output_file}")
    value = File.read(output_file).strip
    # Should not be 'custom', should be the echo command
    assert_no_match(/^custom$/, value)
    assert_match(/echo.*RUBISH_COMMAND/, value)
  end

  def test_rubish_command_not_stored_in_env
    assert_nil ENV['RUBISH_COMMAND'], 'RUBISH_COMMAND should not be stored in ENV'
    execute('echo $RUBISH_COMMAND')
    assert_nil ENV['RUBISH_COMMAND'], 'RUBISH_COMMAND should still not be in ENV after access'
  end

  # Parameter expansion

  def test_rubish_command_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_COMMAND:-default} > #{output_file}")
    value = File.read(output_file).strip
    # RUBISH_COMMAND is set, so should not use default
    assert_no_match(/^default$/, value)
  end

  def test_rubish_command_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_COMMAND:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'RUBISH_COMMAND should be considered set'
  end

  def test_rubish_command_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_COMMAND} > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Length should be positive (the command itself has some length)
    assert value > 0, "Expected positive length, got #{value}"
  end

  # Edge cases

  def test_rubish_command_with_pipeline
    output_file = File.join(@tempdir, 'output.txt')
    execute('echo hello | cat')
    execute("echo $RUBISH_COMMAND > #{output_file}")
    value = File.read(output_file).strip
    # After pipeline, RUBISH_COMMAND should be updated to the echo command
    assert_match(/echo.*RUBISH_COMMAND/, value)
  end

  def test_rubish_command_includes_redirections
    output_file = File.join(@tempdir, 'output.txt')
    dummy_file = File.join(@tempdir, 'dummy.txt')
    execute("echo hello > #{dummy_file}")
    execute("echo $RUBISH_COMMAND > #{output_file}")
    value = File.read(output_file).strip
    # RUBISH_COMMAND should reflect the echo command, not the previous one with redirect
    assert_match(/echo.*RUBISH_COMMAND/, value)
  end

  def test_rubish_command_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $RUBISH_COMMAND) > #{output_file}")
    value = File.read(output_file).strip
    # In subshell, RUBISH_COMMAND should be set
    assert value.length > 0, 'Expected RUBISH_COMMAND to have content in subshell'
  end

  def test_rubish_command_initial_value
    # Fresh REPL should have RUBISH_COMMAND as empty initially
    repl = Rubish::REPL.new
    rubish_command = repl.instance_variable_get(:@rubish_command)
    assert_equal '', rubish_command
  end

  def test_rubish_command_after_alias_expansion
    # Set up an alias
    execute('alias greet="echo hello"')
    execute('greet')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_COMMAND > #{output_file}")
    value = File.read(output_file).strip
    # Should reflect the current command (echo), not the aliased one
    assert_match(/echo.*RUBISH_COMMAND/, value)
  end

  def test_rubish_command_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo first > #{output_file1}")
    repl2.send(:execute, "echo second > #{output_file2}")

    rubish_cmd1 = repl1.instance_variable_get(:@rubish_command)
    rubish_cmd2 = repl2.instance_variable_get(:@rubish_command)

    assert_match(/first/, rubish_cmd1)
    assert_match(/second/, rubish_cmd2)
  end
end
