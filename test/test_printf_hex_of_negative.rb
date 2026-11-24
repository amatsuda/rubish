# frozen_string_literal: true

require_relative 'test_helper'

# printf %x, %o and %X of a negative number print the 64-bit two's complement (bash)
class TestPrintfHexOfNegative < Test::Unit::TestCase
  def test_conversions
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', "printf '%x %X %o\\n' -1 -1 -1; printf '%x\\n' 255", err: %i[child out]], &:read)
    assert_equal "ffffffffffffffff FFFFFFFFFFFFFFFF 1777777777777777777777\nff\n", out
  end
end
