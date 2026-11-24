# frozen_string_literal: true

require_relative 'test_helper'

# A negative length in ${arr[@]:offset:length} is an error (bash)
class TestArraySliceNegativeLengthError < Test::Unit::TestCase
  def test_error
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'arr=(a b c); echo "${arr[@]:1:-1}"; echo not', err: err_w], &:read)
    err_w.close
    assert_equal '', out
    assert_equal 1, $?.exitstatus
    assert_equal "rubish: -1: substring expression < 0\n", err_r.read
  ensure
    err_r&.close
  end
end
