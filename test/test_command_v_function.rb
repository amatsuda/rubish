# frozen_string_literal: true

require_relative 'test_helper'

class TestCommandVFunction < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  # command -V / -v know about functions and builtins
  def test_command_v_reports_a_function
    execute('f_cv() { :; }')
    out = capture_stdout { execute('command -V f_cv; command -v f_cv') }
    assert_equal "f_cv is a function\nf_cv\n", out
  end
end
