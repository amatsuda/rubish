# frozen_string_literal: true

require_relative 'test_helper'

# errexit (set -e) details that follow bash: a negated command does not
# exit, a failing command substitution in an assignment does, and with
# pipefail a failing pipeline does
class TestErrexitCases < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', script, err: File::NULL], &:read)
    [out, $?.exitstatus]
  end

  def test_negated_command_does_not_trigger_errexit
    assert_equal ["yes\n", 0], run_shell('set -e; ! true; echo yes')
  end

  def test_pipefail_failure_exits
    assert_equal ['', 1], run_shell('set -eo pipefail; false | true; echo not')
  end

  def test_pipeline_without_pipefail_goes_on
    assert_equal ["pipe\n", 0], run_shell('set -e; false | true; echo pipe')
  end
end
