# frozen_string_literal: true

require_relative 'test_helper'

# `source` without a file name is a usage error: status 2, message on stderr
class TestSourceUsageStatus < Test::Unit::TestCase
  def test_status_and_message
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'source; echo $?; .; echo $?', err: err_w], &:read)
    err_w.close
    assert_equal "2\n2\n", out
    assert_match(/source: filename argument required\nsource: usage: source/, err_r.read)
  ensure
    err_r&.close
  end
end
