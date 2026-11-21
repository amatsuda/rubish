# frozen_string_literal: true

require_relative 'test_helper'

# `${var@Q}` quotes the value; an unset variable has none and expands to
# nothing, while an empty one quotes to ''
class TestTransformQuoteUnset < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    execute('unset s')
  end

  def test_unset_variable_expands_to_nothing
    out = capture_stdout { execute('echo "[${s@Q}]"') }
    assert_equal "[]\n", out
  end

  def test_empty_variable_quotes_to_empty_quotes
    execute('s=')
    out = capture_stdout { execute('echo "[${s@Q}]"') }
    assert_equal "['']\n", out
  end
end
