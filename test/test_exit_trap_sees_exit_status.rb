# frozen_string_literal: true

require_relative 'test_helper'

# Inside the EXIT trap, $? is the status the shell is exiting with
class TestExitTrapSeesExitStatus < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', script, err: File::NULL], &:read)
    [out, $?.exitstatus]
  end

  def test_explicit_exit_code
    assert_equal ["last 9\n", 9], run_shell("trap 'echo last $?' EXIT; exit 9")
  end

  def test_exit_from_a_signal_trap
    assert_equal ["int\nfrom trap 3\n", 3], run_shell("trap 'echo \"from trap $?\"' EXIT; trap 'echo int; exit 3' INT; kill -INT $$; echo not")
  end

  def test_exit_trap_runs_once_for_a_pipeline_ending_in_exit
    assert_equal ["w\n", 5], run_shell("trap 'echo w' EXIT; echo a | exit 5")
  end
end
