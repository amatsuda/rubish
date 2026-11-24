# frozen_string_literal: true

require_relative 'test_helper'

# ${#b[@]} of an unset variable is an error under set -u; an empty array is 0
class TestNounsetArrayLength < Test::Unit::TestCase
  def test_unset_and_empty
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'set -u; a=(); echo ${#a[@]}; unset b; echo "${#b[@]}"; echo not', err: err_w], &:read)
    err_w.close
    assert_equal "0\n", out
    assert_equal 1, $?.exitstatus
    assert_match(/b: unbound variable/, err_r.read)
  ensure
    err_r&.close
  end
end
