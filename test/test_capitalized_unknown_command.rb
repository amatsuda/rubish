# frozen_string_literal: true

require_relative 'test_helper'

# A capitalized word that names no Ruby constant is an unknown command, not
# a Ruby error
class TestCapitalizedUnknownCommand < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_unknown_capitalized_word
    err = capture_stderr { execute('Nosuchcmd_zz') }
    assert_equal "rubish: Nosuchcmd_zz: command not found\n", err
    assert_equal 127, @repl.instance_variable_get(:@last_status)
  end

  def test_ruby_constant_still_evaluates
    out = capture_stdout { execute('Math.sqrt(16).to_i') }
    assert_match(/4/, out)
  end
end
