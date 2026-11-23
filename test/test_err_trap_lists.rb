# frozen_string_literal: true

require_relative 'test_helper'

# The ERR trap follows errexit's rules: not for a command followed by `&&`
# or `||`, not for a negated command, once for a failing function call at
# the caller's level, and inside functions only with errtrace
class TestErrTrapLists < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_not_for_the_left_side_of_and_or_lists
    assert_equal "done\n", run_shell("trap 'echo e' ERR; false || true; false && true; echo done")
  end

  def test_not_for_a_negated_command
    assert_equal "done\n", run_shell("trap 'echo e' ERR; ! false; echo done")
  end
end
