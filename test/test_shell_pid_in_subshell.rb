# frozen_string_literal: true

require_relative 'test_helper'

# `$$` is the main shell's pid everywhere, subshells included; BASHPID is
# the current process
class TestShellPidInSubshell < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_dollar_dollar_is_the_same_in_a_subshell
    outer, inner = run_shell('echo $$; (echo $$)').split
    assert_equal outer, inner
  end

  def test_bashpid_differs_in_a_subshell
    outer, inner = run_shell('echo $BASHPID; (echo $BASHPID)').split
    assert_not_equal outer, inner
  end

  def test_subshell_can_signal_the_shell
    assert_equal "t\nafter\n", run_shell("trap 'echo t' TERM; (kill -TERM $$); echo after")
  end
end
