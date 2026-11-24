# frozen_string_literal: true

require_relative 'test_helper'

# FUNCNEST set as a shell variable limits function nesting
class TestFuncnestShellVariable < Test::Unit::TestCase
  def test_limit
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'FUNCNEST=3; f() { echo $1; f $(( $1 + 1 )); }; f 1 2>&1 | head -5', err: %i[child out]], &:read)
    lines = out.lines
    assert_equal %W[1\n 2\n 3\n], lines.first(3)
    assert_match(/f: maximum function nesting level exceeded \(3\)/, lines[3].to_s)
    assert_equal 4, lines.length
  end
end
