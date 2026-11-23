# frozen_string_literal: true

require_relative 'test_helper'

# Brace expansion: an empty alternative yields the surrounding text alone,
# and an alternative may be quoted
class TestBraceEmptyAndQuotedAlternatives < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_empty_alternatives
    out = capture_stdout { execute('echo x{,} {,}x {a,}b') }
    assert_equal "x x x x ab b\n", out
  end

  def test_quoted_alternative
    out = capture_stdout { execute('for w in {a,"b c"} {d,\'e f\'}; do echo "[$w]"; done') }
    assert_equal "[a]\n[b c]\n[d]\n[e f]\n", out
  end
end
