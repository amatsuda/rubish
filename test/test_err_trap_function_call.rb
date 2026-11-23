# frozen_string_literal: true

require_relative 'test_helper'

# A failing function call runs the ERR trap at the call site; inside the
# function it runs only with errtrace, as in bash
class TestErrTrapFunctionCall < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_failing_function_call_fires_at_the_call_site
    assert_equal "e\nmid\n", run_shell("trap 'echo e' ERR; f() { false; }; f; echo mid")
  end

  def test_errtrace_fires_inside_the_function_too
    assert_equal "e\ne\n", run_shell("set -o errtrace; trap 'echo e' ERR; f() { false; }; f")
  end
end
