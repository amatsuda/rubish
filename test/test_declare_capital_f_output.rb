# frozen_string_literal: true

require_relative 'test_helper'

# `declare -F name` prints just the name, as bash does
class TestDeclareCapitalFOutput < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_name_only
    out = capture_stdout { execute('f() { :; }; declare -F f; echo $?') }
    assert_equal "f\n0\n", out
  end
end
