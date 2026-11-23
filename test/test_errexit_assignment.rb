# frozen_string_literal: true

require_relative 'test_helper'

# An assignment whose command substitution fails is a failing command:
# errexit exits on it and the ERR trap runs
class TestErrexitAssignment < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', script, err: File::NULL], &:read)
    [out, $?.exitstatus]
  end

  def test_failing_substitution_in_an_assignment_exits
    assert_equal ['', 1], run_shell('set -e; x=$(false); echo not')
  end

  def test_failing_substitution_runs_the_err_trap
    assert_equal "e\n", run_shell("trap 'echo e' ERR; x=$(false); true")[0]
  end
end
