# frozen_string_literal: true

require_relative 'test_helper'

# `type f` prints the function's definition after naming it, as bash does
class TestTypeFunctionBody < Test::Unit::TestCase
  def test_body_is_printed
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'f() { echo hi; }; type f', err: File::NULL], &:read)
    lines = out.lines
    assert_equal "f is a function\n", lines.first
    assert_match(/echo hi/, out)
    assert_equal "}\n", lines.last
  end
end
