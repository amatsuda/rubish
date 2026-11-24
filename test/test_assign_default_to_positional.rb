# frozen_string_literal: true

require_relative 'test_helper'

# `${2:=e}` cannot assign to a positional parameter
class TestAssignDefaultToPositional < Test::Unit::TestCase
  def test_error
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'set -- a; echo "${2:=e}" x; echo not', err: err_w], &:read)
    err_w.close
    # the expansion error ends a non-interactive shell with status 1 (bash)
    assert_equal '', out
    assert_equal 1, $?.exitstatus
    assert_equal "rubish: $2: cannot assign in this way\n", err_r.read
  ensure
    err_r&.close
  end
end
