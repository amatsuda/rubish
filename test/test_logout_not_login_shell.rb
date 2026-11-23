# frozen_string_literal: true

require_relative 'test_helper'

# logout in a non-login shell complains and goes on, as bash does
class TestLogoutNotLoginShell < Test::Unit::TestCase
  def test_does_not_exit
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'logout; echo "after $?"', err: err_w], &:read)
    err_w.close
    assert_equal "after 1\n", out
    assert_match(/logout: not login shell: use `exit'/, err_r.read)
  ensure
    err_r&.close
  end
end
