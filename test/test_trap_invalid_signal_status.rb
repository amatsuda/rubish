# frozen_string_literal: true

require_relative 'test_helper'

# An unknown signal makes trap fail with status 1 and bash's message
class TestTrapInvalidSignalStatus < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_unknown_name
    err = capture_stderr { @out = capture_stdout { execute("trap 'echo bad' BADSIG; echo $?") } }
    assert_equal "1\n", @out
    assert_match(/trap: BADSIG: invalid signal specification/, err)
  end

  def test_unknown_number
    err = capture_stderr { @out = capture_stdout { execute("trap 'echo x' 99; echo $?") } }
    assert_equal "1\n", @out
    assert_match(/trap: 99: invalid signal specification/, err)
  end
end
