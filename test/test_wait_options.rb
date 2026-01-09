# frozen_string_literal: true

require_relative 'test_helper'

class TestWaitOptions < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_wait_options_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    Rubish::JobManager.instance.clear
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::JobManager.instance.clear
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test -p option requires argument
  def test_wait_p_requires_argument
    output = capture_stdout do
      result = Rubish::Builtins.run('wait', ['-p'])
      assert_false result
    end
    assert_match(/option requires an argument/, output)
  end

  # Test -p option stores PID in variable
  def test_wait_p_stores_pid
    # Start a background process
    pid = fork { exit 0 }
    Rubish::JobManager.instance.add(pid: pid, pgid: pid, command: 'exit 0')

    ENV.delete('WAITED_PID')
    Rubish::Builtins.run('wait', ['-p', 'WAITED_PID', pid.to_s])

    assert_equal pid.to_s, ENV['WAITED_PID']
  end

  # Test -p with all jobs
  def test_wait_p_with_all_jobs
    pid = fork { exit 0 }
    Rubish::JobManager.instance.add(pid: pid, pgid: pid, command: 'exit 0')

    ENV.delete('WAITED_PID')
    Rubish::Builtins.run('wait', ['-p', 'WAITED_PID'])

    # Should have stored the PID of the waited process
    assert_not_nil ENV['WAITED_PID']
    assert_equal pid.to_s, ENV['WAITED_PID']
  end

  # Test -n option with no jobs returns true
  def test_wait_n_no_jobs
    result = Rubish::Builtins.run('wait', ['-n'])
    assert result
  end

  # Test -n option waits for any single job
  def test_wait_n_waits_for_any
    # Start multiple background processes
    pid1 = fork { sleep 0.01; exit 1 }
    pid2 = fork { sleep 0.5; exit 2 }

    Rubish::JobManager.instance.add(pid: pid1, pgid: pid1, command: 'short')
    Rubish::JobManager.instance.add(pid: pid2, pgid: pid2, command: 'long')

    ENV.delete('WAITED_PID')
    start_time = Time.now

    result = Rubish::Builtins.run('wait', ['-n', '-p', 'WAITED_PID'])
    elapsed = Time.now - start_time

    # Should have waited for the shorter process (pid1)
    assert_equal pid1.to_s, ENV['WAITED_PID']
    # Should return false because exit 1
    assert_false result
    # Should not have waited the full 0.5 seconds
    assert elapsed < 0.4

    # Clean up remaining process
    Process.kill('TERM', pid2) rescue nil
    Process.wait(pid2) rescue nil
  end

  # Test -n with specific PIDs
  def test_wait_n_with_specific_pids
    pid1 = fork { sleep 0.3; exit 0 }
    pid2 = fork { sleep 0.01; exit 0 }

    Rubish::JobManager.instance.add(pid: pid1, pgid: pid1, command: 'slow')
    Rubish::JobManager.instance.add(pid: pid2, pgid: pid2, command: 'fast')

    ENV.delete('WAITED_PID')
    result = Rubish::Builtins.run('wait', ['-n', '-p', 'WAITED_PID', pid2.to_s])

    # Should wait for pid2 specifically
    assert_equal pid2.to_s, ENV['WAITED_PID']
    assert result

    # Clean up
    Process.kill('TERM', pid1) rescue nil
    Process.wait(pid1) rescue nil
  end

  # Test -f option is accepted (behavior is same as without -f in our implementation)
  def test_wait_f_option_accepted
    pid = fork { exit 0 }
    Rubish::JobManager.instance.add(pid: pid, pgid: pid, command: 'exit 0')

    result = Rubish::Builtins.run('wait', ['-f', pid.to_s])
    assert result
  end

  # Test combined options -fn
  def test_wait_combined_fn
    pid = fork { exit 0 }
    Rubish::JobManager.instance.add(pid: pid, pgid: pid, command: 'exit 0')

    ENV.delete('WAITED_PID')
    result = Rubish::Builtins.run('wait', ['-fn', '-p', 'WAITED_PID'])

    assert_equal pid.to_s, ENV['WAITED_PID']
  end

  # Test combined options -nf
  def test_wait_combined_nf
    pid = fork { exit 0 }
    Rubish::JobManager.instance.add(pid: pid, pgid: pid, command: 'exit 0')

    ENV.delete('WAITED_PID')
    result = Rubish::Builtins.run('wait', ['-nf', '-p', 'WAITED_PID'])

    assert_equal pid.to_s, ENV['WAITED_PID']
  end

  # Test invalid option
  def test_wait_invalid_option
    output = capture_stdout do
      result = Rubish::Builtins.run('wait', ['-x'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test -p with job spec
  def test_wait_p_with_job_spec
    pid = fork { exit 0 }
    job = Rubish::JobManager.instance.add(pid: pid, pgid: pid, command: 'exit 0')

    ENV.delete('WAITED_PID')
    Rubish::Builtins.run('wait', ['-p', 'WAITED_PID', "%#{job.id}"])

    assert_equal pid.to_s, ENV['WAITED_PID']
  end

  # Test help shows new options
  def test_help_shows_wait_options
    help = Rubish::Builtins::BUILTIN_HELP['wait']

    assert_not_nil help
    assert_match(/-p/, help[:synopsis])
    assert_match(/fn/, help[:synopsis])  # -fn contains both -f and -n
    assert help[:options].key?('-p VARNAME')
    assert help[:options].key?('-n')
    assert help[:options].key?('-f')
  end

  # Test -n returns success status of exited process
  def test_wait_n_returns_exit_status
    pid_success = fork { exit 0 }
    Rubish::JobManager.instance.add(pid: pid_success, pgid: pid_success, command: 'success')

    result = Rubish::Builtins.run('wait', ['-n'])
    assert result

    pid_fail = fork { exit 1 }
    Rubish::JobManager.instance.add(pid: pid_fail, pgid: pid_fail, command: 'fail')

    result = Rubish::Builtins.run('wait', ['-n'])
    assert_false result
  end

  # Test wait with -p combined in single arg like -pVAR
  def test_wait_p_combined_arg
    pid = fork { exit 0 }
    Rubish::JobManager.instance.add(pid: pid, pgid: pid, command: 'exit 0')

    ENV.delete('MYPID')
    Rubish::Builtins.run('wait', ['-pMYPID', pid.to_s])

    assert_equal pid.to_s, ENV['MYPID']
  end
end
