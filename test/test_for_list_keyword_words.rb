# frozen_string_literal: true

require_relative 'test_helper'

# Words in a for list may look like keywords (`do`, `done`, `def`, `in`)
class TestForListKeywordWords < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_keyword_like_words_are_items
    out = capture_stdout { execute('for w in abc def do done in; do echo $w; done') }
    assert_equal "abc\ndef\ndo\ndone\nin\n", out
  end
end
