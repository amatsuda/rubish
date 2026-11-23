# frozen_string_literal: true

require_relative 'test_helper'

# A lone `[` is an ordinary word: `type [` names the test builtin
class TestTypeBracketArgument < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_type_of_bracket
    out = capture_stdout { execute('type [; type -t [') }
    assert_equal "[ is a shell builtin\nbuiltin\n", out
  end

  def test_bracket_as_an_echo_argument
    out = capture_stdout { execute('echo [ x; echo [') }
    assert_equal "[ x\n[\n", out
  end
end
