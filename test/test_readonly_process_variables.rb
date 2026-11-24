# frozen_string_literal: true

require_relative 'test_helper'

# UID, EUID and PPID are readonly (bash)
class TestReadonlyProcessVariables < Test::Unit::TestCase
  def test_assignment_refused
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'echo "${UID:+set}"; UID=1; echo "after $?"', err: err_w], &:read)
    err_w.close
    assert_equal "set\n", out
    assert_equal 1, $?.exitstatus
    assert_equal "rubish: UID: readonly variable\n", err_r.read
  ensure
    err_r&.close
  end
end
