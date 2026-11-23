# frozen_string_literal: true

require_relative 'test_helper'

# `let` alone reports "expression expected" and fails
class TestLetBare < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_bare_let
    err = capture_stderr { @out = capture_stdout { execute('let; echo $?') } }
    assert_equal "1\n", @out
    assert_equal "rubish: let: expression expected\n", err
  end
end
