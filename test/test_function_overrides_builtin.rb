# frozen_string_literal: true

require_relative 'test_helper'

# A shell function with the same name as a builtin takes precedence (bash),
# e.g. the common `cd() { builtin cd "$@" && ls; }` wrapper
class TestFunctionOverridesBuiltin < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    execute('echo() { builtin echo "wrapped:" "$@"; }')
  end

  def teardown
    execute('unset -f echo')
    Rubish::Builtins.unset(%w[x])
  end

  def test_top_level_simple_command
    out = capture_stdout { execute('echo hi') }
    assert_equal "wrapped: hi\n", out
  end

  def test_inside_a_list
    out = capture_stdout { execute('true; echo hi') }
    assert_equal "wrapped: hi\n", out
  end

  def test_inside_a_condition
    out = capture_stdout { execute('if echo hi; then :; fi') }
    assert_equal "wrapped: hi\n", out
  end

  def test_inside_command_substitution
    execute('x=$(echo hi)')
    assert_equal 'wrapped: hi', get_shell_var('x')
  end

  def test_process_builtin_override_in_list
    execute('cd() { builtin echo "cd-wrapper $1"; }')
    out = capture_stdout { execute('true; cd /tmp') }
    assert_equal "cd-wrapper /tmp\n", out
  ensure
    execute('unset -f cd')
  end

  def test_builtin_keyword_still_reaches_the_builtin
    out = capture_stdout { execute('builtin echo plain') }
    assert_equal "plain\n", out
  end
end
