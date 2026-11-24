# frozen_string_literal: true

require_relative 'test_helper'

# Waiting again for the last background pid gives its remembered status (bash)
class TestWaitRemembersLastAsyncStatus < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_second_wait
    out, err = run_shell('(exit 3) & p=$!; wait $p; echo $?; wait $p; echo $?')
    assert_equal "3\n3\n", out
    assert_equal '', err
  end

  def test_other_reaped_pid_is_still_unknown
    out, err = run_shell('true & p=$!; sleep 0.1 & wait; wait $p; echo $?')
    assert_equal "127\n", out
    assert_match(/not a child of this shell/, err)
  end
end
