# frozen_string_literal: true

require_relative 'test_helper'

# A subshell does not run the parent's EXIT trap, but does run one set
# inside it when it ends
class TestSubshellExitTrap < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', script, err: File::NULL], &:read)
    [out, $?.exitstatus]
  end

  def test_parent_exit_trap_does_not_run_in_the_subshell
    assert_equal ["e2\n", 2], run_shell("trap 'echo e$?' EXIT; (exit 2)")
  end

  def test_parent_exit_trap_runs_once_at_the_end
    assert_equal ["in\nout\nparent\n", 0], run_shell("trap 'echo parent' EXIT; (echo in); echo out")
  end

  def test_subshells_own_exit_trap_runs_when_it_ends
    assert_equal ["in\nsubexit\nout\n", 0], run_shell("(trap 'echo subexit' EXIT; echo in); echo out")
  end
end
