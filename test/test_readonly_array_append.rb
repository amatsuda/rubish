# frozen_string_literal: true

require_relative 'test_helper'

# A compound assignment to a readonly array is refused
class TestReadonlyArrayAppend < Test::Unit::TestCase
  def test_refused
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'readonly arr=(1 2); arr+=(3); echo $?; arr=(9); echo $?; echo ${#arr[@]} ${arr[0]}', err: err_w], &:read)
    err_w.close
    assert_equal "1\n1\n2 1\n", out
    assert_equal "rubish: arr: readonly variable\nrubish: arr: readonly variable\n", err_r.read
  ensure
    err_r&.close
  end
end
