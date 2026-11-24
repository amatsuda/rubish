# frozen_string_literal: true

require_relative 'test_helper'

# kill's argument errors and job specs behave as in bash
class TestKillArguments < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_invalid_signal_in_l
    out, err = run_shell('kill -l 999; echo $?; kill -l abc; echo $?')
    assert_equal "1\n1\n", out
    assert_equal "rubish: kill: 999: invalid signal specification\nrubish: kill: abc: invalid signal specification\n", err
  end

  def test_signal_without_a_target
    out, err = run_shell('kill -9; echo $?')
    assert_equal "2\n", out
    assert_match(/\Akill: usage: kill \[-s sigspec/, err)
  end

  def test_job_spec
    # the second job is %1 again once the first has been waited for (bash)
    out, = run_shell('sleep 5 & kill -9 %1; wait %1; echo $?; sleep 5 & kill %1; wait %1; echo $?')
    assert_equal "137\n143\n", out
  end
end
