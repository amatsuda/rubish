# frozen_string_literal: true

require_relative 'test_helper'

# shift reports a bad count as bash does
class TestShiftArgumentErrors < Test::Unit::TestCase
  def test_messages
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'shift -1; echo $?; shift abc; echo $?; set -- a; shift 2; echo $?', err: err_w], &:read)
    err_w.close
    assert_equal "1\n2\n1\n", out
    assert_equal "rubish: shift: -1: shift count out of range\nrubish: shift: abc: numeric argument required\n", err_r.read
  ensure
    err_r&.close
  end
end
