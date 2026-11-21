# frozen_string_literal: true

require_relative 'test_helper'

# "${@}" and "${*}" inside double quotes behave as "$@" and "$*"
class TestQuotedBracedAt < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_braced_at_and_star_in_quotes
    @repl.positional_params = ['a', 'b c']
    out = capture_stdout { execute('printf "[%s]" "${@}"; printf "|"; printf "[%s]" "${*}"; echo') }
    assert_equal "[a][b c]|[a b c]\n", out
  end

  def test_braced_at_with_no_parameters
    out = capture_stdout { execute('echo "${#}" "${@}" "${*}" end') }
    assert_equal "0  end\n", out
  end
end
