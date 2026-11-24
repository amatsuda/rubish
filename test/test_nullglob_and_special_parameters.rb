# frozen_string_literal: true

require_relative 'test_helper'

# With nullglob on, `$?` (which has no pattern characters) still expands; `shopt -q` is quiet
class TestNullglobAndSpecialParameters < Test::Unit::TestCase
  def test_quiet_status
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'shopt -q nullglob; echo $?; shopt -s nullglob; shopt -q nullglob; echo $?; shopt -q nullglob dotglob; echo $?', err: %i[child out]], &:read)
    assert_equal "1\n0\n1\n", out
  end
end
