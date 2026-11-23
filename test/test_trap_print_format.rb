# frozen_string_literal: true

require_relative 'test_helper'

# `trap -p` prints commands bash can read back: single-quoted, with the
# signal's full name
class TestTrapPrintFormat < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('trap - EXIT INT')
  end

  def test_single_quoted_command
    out = capture_stdout { execute("trap 'echo x' EXIT; trap -p EXIT") }
    assert_equal "trap -- 'echo x' EXIT\n", out
  end

  def test_signal_name_is_the_full_name
    out = capture_stdout { execute("trap 'echo' INT; trap -p INT") }
    assert_equal "trap -- 'echo' SIGINT\n", out
  end

  def test_embedded_single_quote
    out = capture_stdout { execute(%q{trap "echo 'q'" EXIT; trap -p EXIT}) }
    assert_equal "trap -- 'echo '\\''q'\\''' EXIT\n", out
  end
end
