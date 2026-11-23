# frozen_string_literal: true

require_relative 'test_helper'

# `{var}<<< word` opens a herestring on a fresh descriptor whose number
# lands in var, like `{var}<file` does for a file
class TestVarnameHerestring < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_exec_opens_a_herestring_on_a_variable_descriptor
    out = capture_stdout { execute('exec {fd}<<< data; read x <&$fd; echo "$x"; exec {fd}<&-') }
    assert_equal "data\n", out
  end

  def test_herestring_descriptor_for_a_single_command
    out = capture_stdout { execute('{ read -u $fd l; echo "$l"; } {fd}<<< "one two"') }
    assert_equal "one two\n", out
  end
end
