# frozen_string_literal: true

require_relative 'test_helper'

# A bare assignment's exit status is that of the last command substitution
# it ran, or 0 when it ran none (bash semantics). This is what makes
# `if ! out=$(cmd); then ...` work.
class TestAssignmentExitStatus < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    Rubish::Builtins.unset(%w[x y])
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  def test_assignment_from_failing_substitution_fails
    execute('x=$(false)')
    assert_equal 1, last_status
  end

  def test_assignment_from_failing_substitution_keeps_its_status
    execute('x=$(exit 4)')
    assert_equal 4, last_status
  end

  def test_assignment_from_successful_substitution_succeeds
    execute('false')
    execute('x=$(true)')
    assert_equal 0, last_status
  end

  def test_plain_assignment_resets_status_to_zero
    execute('false')
    execute('x=1')
    assert_equal 0, last_status
  end

  def test_assignment_status_inside_list
    execute('true; x=$(false)')
    assert_equal 1, last_status
  end

  def test_last_substitution_wins_with_several_assignments
    execute('x=$(false) y=$(true)')
    assert_equal 0, last_status
  end

  def test_negated_assignment_in_if
    out = capture_stdout { execute('if ! x=$(false); then echo failed; else echo ok; fi') }
    assert_equal "failed\n", out
  end
end
