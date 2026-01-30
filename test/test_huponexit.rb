# frozen_string_literal: true

require_relative 'test_helper'

class TestHuponexit < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    Rubish::JobManager.instance.clear
    @tempdir = Dir.mktmpdir('rubish_huponexit_test')
  end

  def teardown
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    Rubish::JobManager.instance.clear
    FileUtils.rm_rf(@tempdir)
  end

  # huponexit is disabled by default
  def test_huponexit_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('huponexit')
  end

  def test_huponexit_can_be_enabled
    execute('shopt -s huponexit')
    assert Rubish::Builtins.shopt_enabled?('huponexit')
  end

  def test_huponexit_can_be_disabled
    execute('shopt -s huponexit')
    execute('shopt -u huponexit')
    assert_false Rubish::Builtins.shopt_enabled?('huponexit')
  end

  # Test that send_hup_to_active_jobs handles empty job list
  def test_send_hup_no_jobs
    # Should not raise any errors
    assert_nothing_raised do
      Rubish::Builtins.send_hup_to_active_jobs
    end
  end

  # Test that send_hup_to_active_jobs handles done jobs
  def test_send_hup_skips_done_jobs
    # Add a done job
    job = Rubish::JobManager.instance.add(pid: 99999, pgid: 99999, command: 'finished')
    job.status = :done

    # Should not raise any errors (done jobs are not active)
    assert_nothing_raised do
      Rubish::Builtins.send_hup_to_active_jobs
    end
  end

  # Test that send_hup_to_active_jobs handles nonexistent process gracefully
  def test_send_hup_handles_esrch
    # Add a fake job with nonexistent PID
    Rubish::JobManager.instance.add(pid: 999999999, pgid: 999999999, command: 'fake')

    # Should not raise any errors
    assert_nothing_raised do
      Rubish::Builtins.send_hup_to_active_jobs
    end
  end

  # Test that exit sends SIGHUP when huponexit is enabled
  def test_exit_sends_sighup_with_huponexit
    execute('shopt -s huponexit')

    # Create a marker file to verify SIGHUP was received
    marker_file = File.join(@tempdir, 'hup_received')

    # Start a subprocess that writes to marker file when it receives SIGHUP
    pid = fork do
      # Set up SIGHUP handler
      trap('HUP') do
        File.write(marker_file, 'received')
        exit(0)
      end

      # Create a new process group so we can send signals to it
      Process.setpgid(0, 0)

      # Write our PID to a file so parent knows our pgid
      File.write(File.join(@tempdir, 'child_pid'), Process.pid.to_s)

      # Sleep and wait for signal
      sleep 10
    end

    # Wait for child to set up
    sleep 0.1 until File.exist?(File.join(@tempdir, 'child_pid'))
    child_pid = File.read(File.join(@tempdir, 'child_pid')).to_i

    # Add the job to JobManager with correct pgid
    Rubish::JobManager.instance.add(pid: child_pid, pgid: child_pid, command: 'sleep 10')

    # Exit should send SIGHUP
    catch(:exit) do
      Rubish::Builtins.run('exit', ['0'])
    end

    # Wait for child to handle signal
    sleep 0.2

    # Verify SIGHUP was received
    assert File.exist?(marker_file), 'SIGHUP should have been sent to the job'

    # Clean up
    begin
      Process.kill('KILL', child_pid)
    rescue Errno::ESRCH
      # Already gone
    end
    Process.wait(child_pid) rescue nil
  end

  # Test that exit does NOT send SIGHUP when huponexit is disabled
  def test_exit_no_sighup_without_huponexit
    # huponexit is disabled by default

    # Create a marker file to verify SIGHUP was NOT received
    marker_file = File.join(@tempdir, 'hup_received')

    # Start a subprocess that writes to marker file when it receives SIGHUP
    pid = fork do
      # Set up SIGHUP handler
      trap('HUP') do
        File.write(marker_file, 'received')
        exit(0)
      end

      Process.setpgid(0, 0)
      File.write(File.join(@tempdir, 'child_pid'), Process.pid.to_s)
      sleep 10
    end

    # Wait for child to set up
    sleep 0.1 until File.exist?(File.join(@tempdir, 'child_pid'))
    child_pid = File.read(File.join(@tempdir, 'child_pid')).to_i

    # Add the job to JobManager
    Rubish::JobManager.instance.add(pid: child_pid, pgid: child_pid, command: 'sleep 10')

    # Exit should NOT send SIGHUP
    catch(:exit) do
      Rubish::Builtins.run('exit', ['0'])
    end

    # Wait a moment
    sleep 0.2

    # Verify SIGHUP was NOT received
    assert_false File.exist?(marker_file), 'SIGHUP should NOT have been sent without huponexit'

    # Clean up
    begin
      Process.kill('KILL', child_pid)
    rescue Errno::ESRCH
      # Already gone
    end
    Process.wait(child_pid) rescue nil
  end

  # Test that logout also respects huponexit
  def test_logout_sends_sighup_with_huponexit
    execute('shopt -s huponexit')

    # Create a marker file
    marker_file = File.join(@tempdir, 'hup_received')

    pid = fork do
      trap('HUP') do
        File.write(marker_file, 'received')
        exit(0)
      end

      Process.setpgid(0, 0)
      File.write(File.join(@tempdir, 'child_pid'), Process.pid.to_s)
      sleep 10
    end

    sleep 0.1 until File.exist?(File.join(@tempdir, 'child_pid'))
    child_pid = File.read(File.join(@tempdir, 'child_pid')).to_i

    Rubish::JobManager.instance.add(pid: child_pid, pgid: child_pid, command: 'sleep 10')

    # Capture stderr to suppress logout warning
    original_stderr = $stderr
    $stderr = StringIO.new

    catch(:exit) do
      Rubish::Builtins.run('logout', ['0'])
    end

    $stderr = original_stderr

    sleep 0.2

    assert File.exist?(marker_file), 'SIGHUP should have been sent by logout'

    begin
      Process.kill('KILL', child_pid)
    rescue Errno::ESRCH
    end
    Process.wait(child_pid) rescue nil
  end

  # Test send_hup sends to both running and stopped jobs
  def test_send_hup_to_running_and_stopped_jobs
    # Add running job
    running_job = Rubish::JobManager.instance.add(pid: 999999998, pgid: 999999998, command: 'running')

    # Add stopped job
    stopped_job = Rubish::JobManager.instance.add(pid: 999999997, pgid: 999999997, command: 'stopped')
    stopped_job.status = :stopped

    # Both should be in active jobs
    active = Rubish::JobManager.instance.active
    assert_equal 2, active.length
    assert_includes active, running_job
    assert_includes active, stopped_job

    # send_hup should not raise (processes don't exist, but that's fine)
    assert_nothing_raised do
      Rubish::Builtins.send_hup_to_active_jobs
    end
  end

  # Test huponexit works with checkjobs (they are independent)
  def test_huponexit_with_checkjobs
    execute('shopt -s huponexit')
    execute('shopt -s checkjobs')

    # Add a fake job
    Rubish::JobManager.instance.add(pid: 999999999, pgid: 999999999, command: 'fake')

    # First exit should be blocked by checkjobs
    original_stderr = $stderr
    $stderr = StringIO.new

    result = Rubish::Builtins.run('exit', ['0'])
    assert_false result

    $stderr = original_stderr

    # Second exit should proceed (and send SIGHUP)
    exit_code = catch(:exit) do
      Rubish::Builtins.run('exit', ['42'])
      :no_exit
    end
    assert_equal 42, exit_code
  end
end
