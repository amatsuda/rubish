# frozen_string_literal: true

require_relative 'test_helper'

# A negative subscript before the start of an array is reported (bash)
class TestBadArraySubscriptMessage < Test::Unit::TestCase
  def test_message
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'a=(1 2 3); echo "[${a[-5]}]"; echo $?; echo "${a[-1]}"', err: err_w], &:read)
    err_w.close
    assert_equal "[]\n0\n3\n", out
    assert_equal "rubish: a: bad array subscript\n", err_r.read
  ensure
    err_r&.close
  end
end
