# frozen_string_literal: true

require_relative 'test_helper'

# `unalias name` fails with status 1 when there is no such alias
class TestUnaliasNotFoundStatus < Test::Unit::TestCase
  def test_status_and_message
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'unalias nosuch; echo $?', err: err_w], &:read)
    err_w.close
    assert_equal "1\n", out
    assert_equal "rubish: unalias: nosuch: not found\n", err_r.read
  ensure
    err_r&.close
  end
end
