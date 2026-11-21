# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# `;&` falls through into the next branch's body; `;;&` goes on testing the
# following patterns, as in bash
class TestCaseFallthrough < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_case') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_fallthrough_runs_the_next_body_without_testing
    assert_equal "B\nC\n", run_and_read('case b in a) echo A;; b) echo B;& c) echo C;; d) echo D;; esac')
  end

  def test_continue_testing_runs_every_matching_branch
    assert_equal "B\nB2\n", run_and_read('case b in a) echo A;; b) echo B;;& b) echo B2;; c) echo C;; esac')
  end

  def test_double_semicolon_still_stops
    assert_equal "B\n", run_and_read('case b in b) echo B;; b) echo B2;; esac')
  end
end
