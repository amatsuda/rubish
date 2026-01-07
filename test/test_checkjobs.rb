# frozen_string_literal: true

require_relative 'test_helper'

class TestCheckjobs < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    Rubish::JobManager.instance.clear
    Rubish::Builtins.exit_blocked_by_jobs = false
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    Rubish::JobManager.instance.clear
    Rubish::Builtins.exit_blocked_by_jobs = false
  end

  # checkjobs is disabled by default
  def test_checkjobs_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('checkjobs')
  end

  def test_checkjobs_can_be_enabled
    execute('shopt -s checkjobs')
    assert Rubish::Builtins.shopt_enabled?('checkjobs')
  end

  def test_checkjobs_can_be_disabled
    execute('shopt -s checkjobs')
    execute('shopt -u checkjobs')
    assert_false Rubish::Builtins.shopt_enabled?('checkjobs')
  end

  # Without checkjobs, exit proceeds even with jobs
  def test_exit_without_checkjobs_proceeds_with_jobs
    # Add a fake running job
    Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'sleep 100')

    exit_code = catch(:exit) do
      Rubish::Builtins.run('exit', ['0'])
      :no_exit
    end
    assert_equal 0, exit_code
  end

  # With checkjobs and running jobs, first exit warns
  def test_checkjobs_first_exit_with_running_job_warns
    execute('shopt -s checkjobs')

    # Add a fake running job
    Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'sleep 100')

    stderr = capture_stderr do
      result = Rubish::Builtins.run('exit', ['0'])
      assert_false result
    end
    assert_match(/there are 1 running jobs/, stderr)
    assert Rubish::Builtins.exit_blocked_by_jobs
  end

  # With checkjobs and stopped jobs, first exit warns
  def test_checkjobs_first_exit_with_stopped_job_warns
    execute('shopt -s checkjobs')

    # Add a fake stopped job
    job = Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'sleep 100')
    job.status = :stopped

    stderr = capture_stderr do
      result = Rubish::Builtins.run('exit', ['0'])
      assert_false result
    end
    assert_match(/there are 1 stopped jobs/, stderr)
    assert Rubish::Builtins.exit_blocked_by_jobs
  end

  # With checkjobs and both running and stopped jobs, first exit shows both counts
  def test_checkjobs_first_exit_with_mixed_jobs_warns
    execute('shopt -s checkjobs')

    # Add running and stopped jobs
    Rubish::JobManager.instance.add(pid: 99998, pgid: 99998, command: 'running1')
    Rubish::JobManager.instance.add(pid: 99997, pgid: 99997, command: 'running2')
    job3 = Rubish::JobManager.instance.add(pid: 99996, pgid: 99996, command: 'stopped1')
    job3.status = :stopped

    stderr = capture_stderr do
      result = Rubish::Builtins.run('exit', ['0'])
      assert_false result
    end
    assert_match(/2 running/, stderr)
    assert_match(/1 stopped/, stderr)
  end

  # Second consecutive exit proceeds
  def test_checkjobs_second_exit_proceeds
    execute('shopt -s checkjobs')

    # Add a fake running job
    Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'sleep 100')

    # First exit - should warn
    capture_stderr do
      result = Rubish::Builtins.run('exit', ['0'])
      assert_false result
    end

    # Second exit - should proceed
    exit_code = catch(:exit) do
      Rubish::Builtins.run('exit', ['42'])
      :no_exit
    end
    assert_equal 42, exit_code
  end

  # Non-exit command resets the flag
  def test_non_exit_command_resets_flag
    execute('shopt -s checkjobs')

    # Add a fake running job
    Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'sleep 100')

    # First exit - should warn and set flag
    capture_stderr do
      Rubish::Builtins.run('exit', ['0'])
    end
    assert Rubish::Builtins.exit_blocked_by_jobs

    # Run a non-exit command (echo) - should reset flag via execute()
    execute('echo hello')
    assert_false Rubish::Builtins.exit_blocked_by_jobs

    # Next exit should warn again (not proceed)
    stderr = capture_stderr do
      result = Rubish::Builtins.run('exit', ['0'])
      assert_false result
    end
    assert_match(/there are/, stderr)
  end

  # Exit without jobs doesn't warn
  def test_exit_without_jobs_proceeds
    execute('shopt -s checkjobs')

    exit_code = catch(:exit) do
      Rubish::Builtins.run('exit', ['5'])
      :no_exit
    end
    assert_equal 5, exit_code
  end

  # Done jobs don't count as active
  def test_done_jobs_not_counted
    execute('shopt -s checkjobs')

    # Add a done job
    job = Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'finished')
    job.status = :done

    # Exit should proceed
    exit_code = catch(:exit) do
      Rubish::Builtins.run('exit', ['0'])
      :no_exit
    end
    assert_equal 0, exit_code
  end

  # logout also respects checkjobs
  def test_logout_respects_checkjobs
    execute('shopt -s checkjobs')

    # Add a fake running job
    Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'sleep 100')

    stderr = capture_stderr do
      result = Rubish::Builtins.run('logout', ['0'])
      # logout calls run_exit internally
      assert_false result
    end
    assert_match(/there are 1 running jobs/, stderr)
  end

  # Variable assignment resets flag
  def test_variable_assignment_resets_flag
    execute('shopt -s checkjobs')

    # Add a fake running job
    Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'sleep 100')

    # First exit - should warn and set flag
    capture_stderr do
      Rubish::Builtins.run('exit', ['0'])
    end
    assert Rubish::Builtins.exit_blocked_by_jobs

    # Variable assignment should reset flag
    execute('FOO=bar')
    assert_false Rubish::Builtins.exit_blocked_by_jobs
  end

  # External command resets flag
  def test_external_command_resets_flag
    execute('shopt -s checkjobs')

    # Add a fake running job
    Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'sleep 100')

    # First exit - should warn and set flag
    capture_stderr do
      Rubish::Builtins.run('exit', ['0'])
    end
    assert Rubish::Builtins.exit_blocked_by_jobs

    # External command should reset flag
    execute('/bin/true')
    assert_false Rubish::Builtins.exit_blocked_by_jobs
  end

  # Non-exit builtin resets flag
  def test_non_exit_builtin_resets_flag
    execute('shopt -s checkjobs')

    # Add a fake running job
    Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'sleep 100')

    # First exit - should warn and set flag
    capture_stderr do
      Rubish::Builtins.run('exit', ['0'])
    end
    assert Rubish::Builtins.exit_blocked_by_jobs

    # pwd is a builtin, should reset flag
    execute('pwd')
    assert_false Rubish::Builtins.exit_blocked_by_jobs
  end

  # Flag cleared when no more active jobs
  def test_flag_cleared_when_no_jobs
    execute('shopt -s checkjobs')

    # Add a fake running job
    job = Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'sleep 100')

    # First exit - should warn and set flag
    capture_stderr do
      Rubish::Builtins.run('exit', ['0'])
    end
    assert Rubish::Builtins.exit_blocked_by_jobs

    # Job finishes
    job.status = :done
    Rubish::JobManager.instance.remove(job.id)

    # Exit should now proceed (and clear the flag)
    exit_code = catch(:exit) do
      Rubish::Builtins.run('exit', ['0'])
      :no_exit
    end
    assert_equal 0, exit_code
    assert_false Rubish::Builtins.exit_blocked_by_jobs
  end
end
