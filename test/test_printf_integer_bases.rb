# frozen_string_literal: true

require_relative 'test_helper'

# printf %d/%i/%u/%x/%o accept 0x hex, leading-0 octal and 'c arguments
class TestPrintfIntegerBases < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def printf(fmt, *args)
    capture_stdout { execute("printf '#{fmt}' #{args.join(' ')}") }
  end

  def test_hex_argument
    assert_equal '16', printf('%d', '0x10')
    assert_equal 'ff', printf('%x', '0xFF')
  end

  def test_octal_argument
    assert_equal '8', printf('%d', '010')
    assert_equal '0', printf('%d', '0')
  end

  def test_char_argument
    assert_equal '65', printf('%d', "\"'A\"")
  end

  def test_decimal_and_negative
    assert_equal '-42', printf('%d', '-42')
    assert_equal '7', printf('%i', '7')
  end

  def test_invalid_argument_warns_and_uses_zero
    err = nil
    out = capture_stdout { err = capture_stderr { execute("printf '%d' abc") } }
    assert_equal '0', out
    assert_match(/invalid number/, err)
  end
end
