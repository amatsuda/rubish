# frozen_string_literal: true

require_relative 'test_helper'

# `[[` and `]]` given as arguments are ordinary words: `type [[` works
class TestTypeDoubleBracketArgument < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_type_of_double_brackets
    out = capture_stdout { execute('type [[; type ]]; type time; type -t [[') }
    assert_equal "[[ is a shell keyword\n]] is a shell keyword\ntime is a shell keyword\nkeyword\n", out
  end

  def test_echo_of_double_brackets
    out = capture_stdout { execute('echo [[ x ]]') }
    assert_equal "[[ x ]]\n", out
  end
end
