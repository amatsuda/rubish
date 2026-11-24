# frozen_string_literal: true

require_relative 'test_helper'

# A syntax error in eval's text gives eval the status 2 (bash)
class TestEvalSyntaxErrorStatus < Test::Unit::TestCase
  def test_status
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', "eval 'echo ('; echo $?; eval 'echo ok'", err: err_w], &:read)
    err_w.close
    assert_equal "2\nok\n", out
    assert_match(/syntax error/, err_r.read)
  ensure
    err_r&.close
  end
end
