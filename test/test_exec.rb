# frozen_string_literal: true

require_relative 'test_helper'

class TestExec < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_exec_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test exec is a builtin
  def test_exec_is_builtin
    assert Rubish::Builtins.builtin?('exec')
  end

  # Test exec with no args returns true
  def test_exec_no_args
    result = Rubish::Builtins.run('exec', [])
    assert result
  end

  # Test exec with nonexistent command exits shell (without execfail)
  def test_exec_not_found
    stderr_output = capture_stderr do
      exit_code = catch(:exit) do
        Rubish::Builtins.run('exec', ['nonexistent_command_xyz'])
        :no_exit
      end
      # Without execfail, should exit with 127 (command not found)
      assert_equal 127, exit_code
    end
    assert_match(/not found/, stderr_output)
  end

  # Test exec invalid option
  def test_exec_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('exec', ['-x', 'ls'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test type identifies exec as builtin
  def test_type_identifies_exec_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['exec']) }
    assert_match(/exec is a shell builtin/, output)
  end

  # Test exec actually replaces process (in subprocess)
  def test_exec_replaces_process
    # Fork a subprocess to test exec
    output_file = File.join(@tempdir, 'output.txt')
    pid = fork do
      # Redirect stdout to file
      $stdout.reopen(output_file, 'w')
      Rubish::Builtins.run('exec', ['echo', 'replaced'])
      # This should never run if exec worked
      puts 'NOT REPLACED'
    end
    Process.wait(pid)

    content = File.read(output_file)
    assert_equal "replaced\n", content
    assert_no_match(/NOT REPLACED/, content)
  end

  # Test exec with -a sets argv[0]
  def test_exec_with_a_flag
    output_file = File.join(@tempdir, 'output.txt')
    pid = fork do
      $stdout.reopen(output_file, 'w')
      # Use a command that shows argv[0] - this is tricky
      # For now just verify exec succeeds with -a flag
      Rubish::Builtins.run('exec', ['-a', 'custom_name', 'true'])
    end
    Process.wait(pid)
    assert $?.success?
  end

  # Test exec with absolute path
  def test_exec_absolute_path
    output_file = File.join(@tempdir, 'output.txt')
    pid = fork do
      $stdout.reopen(output_file, 'w')
      Rubish::Builtins.run('exec', ['/bin/echo', 'hello'])
    end
    Process.wait(pid)

    assert_equal "hello\n", File.read(output_file)
  end

  # Test exec with arguments
  def test_exec_with_arguments
    output_file = File.join(@tempdir, 'output.txt')
    pid = fork do
      $stdout.reopen(output_file, 'w')
      Rubish::Builtins.run('exec', ['echo', 'arg1', 'arg2', 'arg3'])
    end
    Process.wait(pid)

    assert_equal "arg1 arg2 arg3\n", File.read(output_file)
  end
end
