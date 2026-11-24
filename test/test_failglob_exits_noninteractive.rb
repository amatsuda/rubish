# frozen_string_literal: true

require_relative 'test_helper'

# A failglob failure ends a non-interactive shell with status 1 (bash)
class TestFailglobExitsNoninteractive < Test::Unit::TestCase
  def test_exit
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'shopt -s failglob; echo *.zzz; echo after', err: err_w], &:read)
    err_w.close
    assert_equal '', out
    assert_equal 1, $?.exitstatus
    assert_match(/no match: \*\.zzz/, err_r.read)
  ensure
    err_r&.close
  end
end
