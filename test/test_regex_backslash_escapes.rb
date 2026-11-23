# frozen_string_literal: true

require_relative 'test_helper'

# In `[[ s =~ re ]]` a backslash-escaped or quoted part of the pattern is
# matched literally, as in bash
class TestRegexBackslashEscapes < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_escaped_dot_is_literal
    out = capture_stdout { execute('[[ "a.c" =~ a\.c ]] && echo esc; [[ "abc" =~ a\.c ]] || echo noesc') }
    assert_equal "esc\nnoesc\n", out
  end

  def test_quoted_part_is_literal
    out = capture_stdout { execute('[[ "a.c" =~ "a.c" ]] && echo q1; [[ "abc" =~ "a.c" ]] || echo q2; [[ "a+b" =~ a"+"b ]] && echo q3') }
    assert_equal "q1\nq2\nq3\n", out
  end

  def test_unquoted_metacharacters_still_work
    out = capture_stdout { execute('[[ abc =~ ^a.c$ ]] && echo m; [[ "a b" =~ a\ b ]] && echo sp') }
    assert_equal "m\nsp\n", out
  end
end
