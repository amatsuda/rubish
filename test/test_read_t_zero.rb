# frozen_string_literal: true

require_relative 'test_helper'

# `read -t 0` reports whether input is available without reading it
class TestReadTZero < Test::Unit::TestCase
  def test_available
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'read -t 0 x < /dev/null; echo $?; echo data | { read -t 0 x; echo $?; read y; echo "$y"; }', err: %i[child out]], &:read)
    assert_equal "0\n0\ndata\n", out
  end
end
