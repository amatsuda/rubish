# frozen_string_literal: true

require_relative 'test_helper'

# A trace line from inside a command substitution or eval repeats PS4's first character
class TestXtraceNestingDepth < Test::Unit::TestCase
  def test_depth
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    IO.popen([exe, '-c', 'set -x; x=$(echo sub); eval "echo e"; echo "$x"', err: err_w], &:read)
    err_w.close
    assert_equal "++ echo sub\n+ x=sub\n+ eval 'echo e'\n++ echo e\n+ echo sub\n", err_r.read
  ensure
    err_r&.close
  end
end
