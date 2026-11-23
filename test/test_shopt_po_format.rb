# frozen_string_literal: true

require_relative 'test_helper'

# `shopt -po name` prints `set -o`/`set +o` lines, as bash does
class TestShoptPoFormat < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('set +e')
  end

  def test_set_o_lines
    out = capture_stdout { execute('shopt -po errexit; shopt -so errexit; shopt -po errexit; shopt -uo errexit') }
    assert_equal "set +o errexit\nset -o errexit\n", out
  end
end
