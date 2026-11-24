# frozen_string_literal: true

require_relative 'test_helper'

# `getopts` with too few arguments is a usage error with status 2
class TestGetoptsUsageStatus < Test::Unit::TestCase
  def test_status
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'getopts; echo $?; getopts a; echo $?', err: File::NULL], &:read)
    assert_equal "2\n2\n", out
  end
end
