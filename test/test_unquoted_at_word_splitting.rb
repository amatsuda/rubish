# frozen_string_literal: true

require_relative 'test_helper'

# Unquoted $@ and $* are word-split like any other unquoted expansion
class TestUnquotedAtWordSplitting < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_unquoted_at_splits_parameters
    @repl.positional_params = ['a', 'b c']
    out = capture_stdout { execute('printf "[%s]" $@; echo; printf "[%s]" $*; echo') }
    assert_equal "[a][b][c]\n[a][b][c]\n", out
  end

  def test_quoted_at_keeps_parameters
    @repl.positional_params = ['a', 'b c']
    out = capture_stdout { execute('printf "[%s]" "$@"; echo') }
    assert_equal "[a][b c]\n", out
  end
end
