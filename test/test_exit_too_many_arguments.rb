# frozen_string_literal: true

require_relative 'test_helper'

# `exit 1 2` in a non-interactive shell reports the error and exits with 1 (bash 5.3)
class TestExitTooManyArguments < Test::Unit::TestCase
  def test_exits
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'exit 1 2; echo not', err: File::NULL], &:read)
    assert_equal '', out
    assert_equal 1, $?.exitstatus
  end
end
