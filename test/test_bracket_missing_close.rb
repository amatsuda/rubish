# frozen_string_literal: true

require_relative 'test_helper'

# `[` without its closing `]` is a syntax error with bash's message
class TestBracketMissingClose < Test::Unit::TestCase
  def test_message_and_status
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', '[ a = ; echo $?; [ a = a ]; echo $?; [ ]; echo $?', err: err_w], &:read)
    err_w.close
    assert_equal "2\n0\n1\n", out
    assert_equal "rubish: [: missing `]'\n", err_r.read
  ensure
    err_r&.close
  end
end
