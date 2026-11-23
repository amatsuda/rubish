# frozen_string_literal: true

require_relative 'test_helper'

# `builtin` alone does nothing and succeeds
class TestBuiltinBare < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_bare_builtin
    err = capture_stderr { @out = capture_stdout { execute('builtin; echo $?') } }
    assert_equal "0\n", @out
    assert_equal '', err
  end
end
