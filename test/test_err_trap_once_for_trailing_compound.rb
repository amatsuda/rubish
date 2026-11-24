# frozen_string_literal: true

require_relative 'test_helper'

# The ERR trap fires once for a failing compound command, even as the last one
class TestErrTrapOnceForTrailingCompound < Test::Unit::TestCase
  def test_once
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'trap "echo E" ERR; (exit 2)', err: %i[child out]], &:read)
    assert_equal "E\n", out
    assert_equal 2, $?.exitstatus
    out = IO.popen([exe, '-c', 'trap "echo E" ERR; { false; }', err: %i[child out]], &:read)
    assert_equal "E\n", out
    out = IO.popen([exe, '-c', 'trap "echo E" ERR; false | false', err: %i[child out]], &:read)
    assert_equal "E\n", out
  end
end
