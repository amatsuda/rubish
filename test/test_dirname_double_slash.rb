# frozen_string_literal: true

require_relative 'test_helper'

# dirname keeps a leading double slash and handles trailing slashes
class TestDirnameDoubleSlash < Test::Unit::TestCase
  def test_cases
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'dirname //a//b//; basename //a//b//; dirname a/b/; dirname /; dirname a; dirname a//b', err: %i[child out]], &:read)
    assert_equal "//a\nb\na\n/\n.\na\n", out
  end
end
