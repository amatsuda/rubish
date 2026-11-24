# frozen_string_literal: true

require_relative 'test_helper'

# $[expr] is the old form of arithmetic expansion, still accepted by bash
class TestDollarBracketArithmetic < Test::Unit::TestCase
  def test_expansion
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'echo $[1+2] $[2*3]; x=4; echo "$[x+1]" "v=$[x*2]"', err: %i[child out]], &:read)
    assert_equal "3 6\n5 v=8\n", out
  end
end
