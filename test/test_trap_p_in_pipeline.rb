# frozen_string_literal: true

require_relative 'test_helper'

# `trap -p` shows the shell's traps even as a pipeline element, as bash does
class TestTrapPInPipeline < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_trap_p_piped
    assert_equal "3\n0\n", run_shell("trap 'echo' 0 1 2; trap -p | wc -l | tr -d ' '; trap - 0 1 2; trap -p | wc -l | tr -d ' '")
  end

  def test_trap_p_redirected
    Dir.mktmpdir do |dir|
      # the EXIT trap itself prints x when the shell ends
      assert_equal "1\nx\n", run_shell("trap 'echo x' EXIT; trap -p > #{dir}/t; wc -l < #{dir}/t | tr -d ' '")
    end
  end
end
