# frozen_string_literal: true

require_relative 'test_helper'

# A case pattern may be a word that is also a keyword elsewhere (`def`, `do`)
class TestCasePatternKeywords < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_keyword_like_alternatives
    out = capture_stdout { execute('x=def; case $x in abc|def) echo "m:$x";; esac; y=do; case $y in do|done) echo "k:$y";; *) echo no;; esac') }
    assert_equal "m:def\nk:do\n", out
  end
end
