# frozen_string_literal: true

require_relative 'test_helper'

class TestExecfail < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_execfail_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
  end

  def test_execfail_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('execfail')
  end

  def test_execfail_can_be_enabled
    execute('shopt -s execfail')
    assert Rubish::Builtins.shopt_enabled?('execfail')
  end

  def test_execfail_can_be_disabled
    execute('shopt -s execfail')
    execute('shopt -u execfail')
    assert_false Rubish::Builtins.shopt_enabled?('execfail')
  end

  def test_exec_not_found_exits_without_execfail
    # Without execfail, exec failure should throw :exit
    exit_code = catch(:exit) do
      Rubish::Builtins.run('exec', ['nonexistent_command_xyz'])
      :no_exit
    end
    # Should have exited with 127 (command not found)
    assert_equal 127, exit_code
  end

  def test_exec_not_found_continues_with_execfail
    execute('shopt -s execfail')
    # With execfail, exec failure should return false but not exit
    exit_code = catch(:exit) do
      result = Rubish::Builtins.run('exec', ['nonexistent_command_xyz'])
      assert_false result
      :no_exit
    end
    # Should NOT have exited
    assert_equal :no_exit, exit_code
  end

  def test_exec_permission_denied_exits_without_execfail
    # Create a file without execute permission
    non_executable = File.join(@tempdir, 'noexec')
    File.write(non_executable, '#!/bin/sh\necho test')
    File.chmod(0o644, non_executable)

    exit_code = catch(:exit) do
      Rubish::Builtins.run('exec', [non_executable])
      :no_exit
    end
    # Should have exited with 126 (permission denied)
    assert_equal 126, exit_code
  end

  def test_exec_permission_denied_continues_with_execfail
    execute('shopt -s execfail')

    # Create a file without execute permission
    non_executable = File.join(@tempdir, 'noexec')
    File.write(non_executable, '#!/bin/sh\necho test')
    File.chmod(0o644, non_executable)

    exit_code = catch(:exit) do
      result = Rubish::Builtins.run('exec', [non_executable])
      assert_false result
      :no_exit
    end
    # Should NOT have exited
    assert_equal :no_exit, exit_code
  end

  def test_exec_no_args_succeeds
    # exec with no arguments should succeed (useful for redirects)
    result = Rubish::Builtins.run('exec', [])
    assert result
  end

  def test_exec_not_found_prints_error
    execute('shopt -s execfail')
    stderr_output = capture_stderr do
      Rubish::Builtins.run('exec', ['nonexistent_cmd_abc123'])
    end
    assert_match(/not found/, stderr_output)
  end

  def test_exec_permission_denied_prints_error
    execute('shopt -s execfail')

    non_executable = File.join(@tempdir, 'noexec2')
    File.write(non_executable, '#!/bin/sh\necho test')
    File.chmod(0o644, non_executable)

    stderr_output = capture_stderr do
      Rubish::Builtins.run('exec', [non_executable])
    end
    assert_match(/permission denied/, stderr_output)
  end
end
