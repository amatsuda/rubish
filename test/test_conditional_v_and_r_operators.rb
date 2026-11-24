# frozen_string_literal: true

require_relative 'test_helper'

# [[ -v arr ]] is true for a set array, and [[ -R name ]] tests for a nameref
class TestConditionalVAndROperators < Test::Unit::TestCase
  def test_operators
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', '[[ -v nosuch_v ]]; echo $?; a=(1); [[ -v a ]]; echo $?; declare -A m=([k]=v); [[ -v m ]]; echo $?; declare -n nr=a; [[ -R nr ]]; echo $?; [[ -R a ]]; echo $?', err: %i[child out]], &:read)
    assert_equal "1\n0\n0\n0\n1\n", out
  end
end
