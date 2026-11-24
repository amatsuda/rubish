# frozen_string_literal: true

require_relative 'test_helper'

# `return` outside a function or sourced file fails with status 2 (bash)
class TestReturnOutsideFunctionStatus < Test::Unit::TestCase
  def test_status
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'return; echo $?', err: File::NULL], &:read)
    assert_equal "2\n", out
  end
end
