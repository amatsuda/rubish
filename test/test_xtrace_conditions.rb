# frozen_string_literal: true

require_relative 'test_helper'

# set -x traces the condition of if and while
class TestXtraceConditions < Test::Unit::TestCase
  def test_traced
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    IO.popen([exe, '-c', 'set -x; if true; then :; fi; while false; do :; done', err: err_w], &:read)
    err_w.close
    assert_equal "+ true\n+ :\n+ false\n", err_r.read
  ensure
    err_r&.close
  end
end
