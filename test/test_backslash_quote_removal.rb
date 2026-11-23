# frozen_string_literal: true

require_relative 'test_helper'

# Backslashes that quote a character are removed from the word: in a for
# list, and before a character that is not a glob metacharacter
class TestBackslashQuoteRemoval < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_escaped_space_in_a_for_list
    out = capture_stdout { execute('for w in a\ b c; do echo "[$w]"; done') }
    assert_equal "[a b]\n[c]\n", out
  end

  def test_escaped_bracket_in_an_argument
    out = capture_stdout { execute('echo \] \[x \{ \~') }
    assert_equal "] [x { ~\n", out
  end
end
