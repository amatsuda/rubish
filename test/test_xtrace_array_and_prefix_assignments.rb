# frozen_string_literal: true

require_relative 'test_helper'

# set -x traces an array assignment, and each prefix assignment on its own line
class TestXtraceArrayAndPrefixAssignments < Test::Unit::TestCase
  def test_traced
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    IO.popen([exe, '-c', 'set -x; a=(1 "b c"); x=1 y="2 3" true; x=1 env | grep -c "^x=1$"', err: err_w], &:read)
    err_w.close
    assert_equal "+ a=(1 'b c')\n+ x=1\n+ y='2 3'\n+ true\n+ x=1\n+ env\n+ grep -c '^x=1$'\n", err_r.read
  ensure
    err_r&.close
  end
end
