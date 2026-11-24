# frozen_string_literal: true

require_relative 'test_helper'

# PS4 is expanded for each trace line, and words with control characters are $'...'-quoted
class TestXtracePs4AndQuoting < Test::Unit::TestCase
  def test_trace
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    IO.popen([exe, '-c', %q{PS4='+${LINENO}+ '; set -x; echo "a b" $'e\tf'}, err: err_w], &:read)
    err_w.close
    assert_equal "+1+ echo 'a b' $'e\\tf'\n", err_r.read
  ensure
    err_r&.close
  end
end
