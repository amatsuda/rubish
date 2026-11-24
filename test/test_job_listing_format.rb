# frozen_string_literal: true

require_relative 'test_helper'

# Job listings use bash's layout: [id] then + for the current job and - for
# the previous one, a padded status, and the command; a job that died from
# a signal is reported as Terminated, Killed, ..., not Done
class TestJobListingFormat < Test::Unit::TestCase
  def setup
    @manager = Rubish::JobManager.instance
    @manager.clear
  end

  def teardown
    @manager.clear
  end

  def test_current_and_previous_markers
    j1 = @manager.add(pid: 1111, pgid: 1111, command: 'sleep 1')
    j2 = @manager.add(pid: 2222, pgid: 2222, command: 'sleep 2')
    # bash's layout: the status padded to 27 columns, a running job with its &
    assert_equal '[1]-  Running                    sleep 1 &', j1.to_s
    assert_equal '[2]+  Running                    sleep 2 &', j2.to_s
  end

  def test_signalled_job_is_reported_by_signal_name
    pid = fork { sleep 30 }
    @manager.add(pid: pid, pgid: pid, command: 'sleep 30')
    Process.kill('TERM', pid)
    sleep 0.2
    out = capture_stdout { @manager.check_background_jobs }
    assert_match(/\A\[1\]\+  Terminated: 15\s+sleep 30\n\z/, out)
  end

  def test_finished_job_is_done
    pid = fork { exit 0 }
    @manager.add(pid: pid, pgid: pid, command: 'true')
    Process.wait(pid) rescue nil
    job = @manager.update_status(pid, Process::Status.allocate) rescue nil
    j = @manager.all.last
    j.status = :done
    assert_equal '[1]+  Done                       true', j.to_s
  end
end
