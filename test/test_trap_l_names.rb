# frozen_string_literal: true

require_relative 'test_helper'

# trap -l lists the signals by their full names
class TestTrapLNames < Test::Unit::TestCase
  def test_lists_full_signal_names
    repl = Rubish::REPL.new
    out = capture_stdout { repl.send(:execute, 'trap -l') }
    assert_match(/\bSIGTERM\b/, out)
    assert_match(/\bSIGINT\b/, out)
  end
end
