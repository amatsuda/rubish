# frozen_string_literal: true

require_relative 'test_helper'

class TestSuspend < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_suspend_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test suspend is a builtin
  def test_suspend_is_builtin
    assert Rubish::Builtins.builtin?('suspend')
  end

  # Test suspend with invalid option
  def test_suspend_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('suspend', ['-x'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test suspend refuses for login shell (SHLVL=1)
  def test_suspend_login_shell_refused
    ENV['SHLVL'] = '1'
    output = capture_output do
      result = Rubish::Builtins.run('suspend', [])
      assert_false result
    end
    assert_match(/cannot suspend a login shell/, output)
  end

  # Test suspend -f forces even for login shell
  def test_suspend_f_forces
    ENV['SHLVL'] = '1'
    # Run in a subprocess so we don't actually suspend the test
    pid = fork do
      Rubish::Builtins.run('suspend', ['-f'])
      exit! 0
    end
    # Send SIGCONT to resume the child
    sleep 0.1
    Process.kill('CONT', pid)
    _, status = Process.waitpid2(pid)
    assert status.success?
  end

  # Test suspend actually stops process (in subprocess)
  def test_suspend_stops_process
    ENV['SHLVL'] = '2'  # Not a login shell
    output_file = File.join(@tempdir, 'output.txt')

    pid = fork do
      File.write(output_file, 'before')
      Rubish::Builtins.run('suspend', [])
      File.write(output_file, 'after')
      exit! 0
    end

    # Wait for the child to suspend
    sleep 0.2
    assert_equal 'before', File.read(output_file)

    # Resume the child
    Process.kill('CONT', pid)
    Process.waitpid(pid)

    assert_equal 'after', File.read(output_file)
  end

  # Test type identifies suspend as builtin
  def test_type_identifies_suspend_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['suspend']) }
    assert_match(/suspend is a shell builtin/, output)
  end
end
