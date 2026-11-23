# frozen_string_literal: true

require_relative 'test_helper'

# printf %q leaves printable non-ASCII characters alone
class TestPrintfQUtf8 < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_non_ascii_letters_are_not_escaped
    out = capture_stdout { execute("printf '%q %q\\n' 'ünïcödé' 'a b'") }
    assert_equal "ünïcödé a\\ b\n", out
  end
end
