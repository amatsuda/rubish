# frozen_string_literal: true

require_relative 'test_helper'

# Background jobs are tracked in scripts too: jobs lists them, wait -n waits
# for the next one, and a bare wait returns 0
class TestJobsInScripts < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_jobs_lists_background_jobs
    out = run_shell('sleep 0.2 & sleep 0.2 & jobs | wc -l | tr -d " "; jobs -p | grep -cE "^[0-9]+$"; jobs -r | wc -l | tr -d " "; jobs -l | grep -cE "^\[[0-9]\][+-]? +[0-9]+ "; wait')
    assert_equal "2\n2\n2\n2\n", out
  end

  def test_wait_n_returns_the_finished_jobs_status
    assert_equal "3\n0\n127\n", run_shell('(exit 3) & sleep 0.3 & wait -n; echo $?; wait -n; echo $?; wait -n; echo $?')
  end

  def test_bare_wait_returns_zero
    assert_equal "0\n", run_shell('(exit 4) & wait; echo $?')
  end

  def test_wait_by_job_spec
    assert_equal "5\n", run_shell('(exit 5) & wait %1; echo $?')
  end
end
