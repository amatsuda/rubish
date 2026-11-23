# frozen_string_literal: true

require_relative 'test_helper'

# printf: %u is a 64-bit unsigned conversion, and an invalid number makes
# the command fail with 1 after printing what it could
class TestPrintfUnsignedAndInvalid < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_unsigned_of_minus_one_is_64_bit
    out = capture_stdout { execute("printf '%u %i\\n' -1 7") }
    assert_equal "18446744073709551615 7\n", out
  end

  def test_invalid_number_fails
    err = capture_stderr { @out = capture_stdout { execute("printf '%d\\n' 0x1f 010 abc; echo $?") } }
    assert_equal "31\n8\n0\n1\n", @out
    assert_match(/printf: abc: invalid number/, err)
  end
end
