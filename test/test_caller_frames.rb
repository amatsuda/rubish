# frozen_string_literal: true

require_relative 'test_helper'

# caller reports the line and file of the current function call, and
# `caller N` adds the calling function's name for frame N
class TestCallerFrames < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_caller_without_argument_prints_line_and_source
    execute('f_c() { caller; }')
    out = capture_stdout { execute('f_c') }
    assert_match(/\A\d+ \S+\n\z/, out)
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_caller_zero_names_the_calling_function
    execute('f_c0() { caller 0; }; g_c0() { f_c0; }')
    out = capture_stdout { execute('g_c0') }
    assert_match(/\A\d+ g_c0 \S+\n\z/, out)
  end

  def test_caller_beyond_the_stack_fails
    # two frames exist (g_c1 from main, f_c1 from g_c1): there is no third
    execute('f_c1() { caller 2; }; g_c1() { f_c1; }')
    out = capture_stdout { execute('g_c1') }
    assert_equal '', out
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_caller_outside_a_function_fails
    out = capture_stdout { execute('caller') }
    assert_equal '', out
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end
end
