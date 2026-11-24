# frozen_string_literal: true

require_relative 'test_helper'

# A backslash-escaped quote inside $(...) inside double quotes does not open a string
class TestEscapedQuoteInSubstitution < Test::Unit::TestCase
  def test_escaped_quotes
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', %q{echo "$(echo \"x\")"; echo next; echo "$(echo 'a\"b')"}, err: %i[child out]], &:read)
    assert_equal "\"x\"\nnext\na\\\"b\n", out
  end
end
