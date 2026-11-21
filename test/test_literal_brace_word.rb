# frozen_string_literal: true

require_relative 'test_helper'

# Braces that are neither a brace expansion nor a brace group are ordinary
# word characters: `echo {a}`, `find . -exec rm {} \;`
class TestLiteralBraceWord < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_braced_word_without_comma_or_range_is_literal
    out = capture_stdout { execute('echo {a}') }
    assert_equal "{a}\n", out
  end

  def test_braces_inside_a_word
    out = capture_stdout { execute('echo x{a}y {} x{}y') }
    assert_equal "x{a}y {} x{}y\n", out
  end

  def test_literal_braces_next_to_an_expansion
    out = capture_stdout { execute('echo {a}{b,c} {a}/{b}') }
    assert_equal "{a}b {a}c {a}/{b}\n", out
  end

  def test_literal_braces_around_an_expansion
    out = capture_stdout { execute('echo {x{1,2}} {{a,b}}') }
    assert_equal "{x1} {x2} {a} {b}\n", out
  end

  def test_brace_group_still_parses
    out = capture_stdout { execute('{ echo grouped; }') }
    assert_equal "grouped\n", out
  end
end
