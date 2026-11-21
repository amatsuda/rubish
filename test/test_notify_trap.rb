# frozen_string_literal: true

require_relative 'test_helper'

# With `set -b` the SIGCHLD trap reports finished jobs at once. Trap
# handlers run in Ruby's trap context, where taking a Mutex raises
# ThreadError, so the job bookkeeping must not lock
class TestNotifyTrap < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @saved_chld = trap('CHLD', 'DEFAULT')
  end

  def teardown
    execute('set +b')
    trap('CHLD', @saved_chld || 'DEFAULT')
  end

  def test_sigchld_with_notify_enabled_does_not_raise
    @repl.send(:setup_signals)
    execute('set -b')
    pid = fork { Process.exit!(0) }
    assert_nothing_raised do
      # the trap runs on the main thread at the next safe point
      5.times { sleep 0.05 }
    end
    Process.wait(pid) rescue nil
  end

  def test_sigchld_with_notify_enabled_reports_the_finished_job
    @repl.send(:setup_signals)
    execute('set -b')
    pid = fork { Process.exit!(0) }
    job = Rubish::JobManager.instance.add(pid: pid, pgid: pid, command: 'exit 0')
    out = capture_stdout { 5.times { sleep 0.05 } }
    assert_match(/\[#{job.id}\].*Done/, out)
  end
end
