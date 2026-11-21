# frozen_string_literal: true

require_relative 'test_helper'

class TestReadonlyFunction < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  # readonly -f protects a function from redefinition
  def test_readonly_function_cannot_be_redefined
    execute('f_ro() { echo original; }; readonly -f f_ro')
    err = capture_stderr { execute('f_ro() { echo redefined; }') }
    assert_match(/f_ro: readonly function/, err)
    out = capture_stdout { execute('f_ro') }
    assert_equal "original\n", out
  end
end
