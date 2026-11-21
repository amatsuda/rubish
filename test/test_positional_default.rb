# frozen_string_literal: true

require_relative 'test_helper'

# "${@:-none}" and "${*:-none}" give the default when there are no
# positional parameters
class TestPositionalDefault < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @repl.positional_params = []
  end

  def test_at_default_when_empty
    out = capture_stdout { execute('echo "${@:-none}" "${*:-also}"') }
    assert_equal "none also\n", out
  end

  def test_at_keeps_parameters_when_present
    @repl.positional_params = %w[p q]
    out = capture_stdout { execute('echo "${@:-none}"') }
    assert_equal "p q\n", out
  end
end
