# frozen_string_literal: true

require_relative 'test_helper'

# A backtick command substitution inside $(( )) is expanded first
class TestArithBacktickSubstitution < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_backtick_substitution
    out = capture_stdout { execute('echo $(( `echo 4` * 2 )) $(( $(echo 2) + 3 ))') }
    assert_equal "8 5\n", out
  end
end
