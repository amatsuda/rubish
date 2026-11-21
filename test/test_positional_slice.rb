# frozen_string_literal: true

require_relative 'test_helper'

# ${@:offset:length} and ${*:offset:length} slice the positional parameters,
# including the ` -1` form that needs a space before a negative offset
class TestPositionalSlice < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @repl.positional_params = %w[p q r]
  end

  def test_negative_offset_with_space
    out = capture_stdout { execute('echo "${@: -1}" "${*: -2}"') }
    assert_equal "r q r\n", out
  end

  def test_offset_and_length
    out = capture_stdout { execute('echo "${*:1:1}" "${@:2}"') }
    assert_equal "p q r\n", out
  end
end
