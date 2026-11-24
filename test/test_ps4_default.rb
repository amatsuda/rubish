# frozen_string_literal: true

require_relative 'test_helper'

# PS4 starts out as "+ ", as in bash
class TestPs4Default < Test::Unit::TestCase
  def test_default
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'echo "[$PS4]"', err: File::NULL], &:read)
    assert_equal "[+ ]\n", out
  end
end
