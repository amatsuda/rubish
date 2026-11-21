# frozen_string_literal: true

require_relative 'test_helper'

# A POSIX character class inside a bracket expression of a pattern operator:
# `${v%%[![:space:]]*}` (the usual way to trim whitespace)
class TestPatternPosixClass < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_negated_posix_class_in_suffix_removal
    execute('v="  trim  "')
    out = capture_stdout { execute('echo "[${v%%[![:space:]]*}]"') }
    assert_equal "[  ]\n", out
  end

  def test_trim_leading_whitespace_idiom
    execute('v="  trim  "')
    out = capture_stdout { execute('echo "[${v#"${v%%[![:space:]]*}"}]"') }
    assert_equal "[trim  ]\n", out
  end

  def test_posix_class_in_prefix_removal
    execute('v="123abc"')
    out = capture_stdout { execute('echo "${v##*[[:digit:]]}" "${v/[[:alpha:]]/X}"') }
    assert_equal "abc 123Xbc\n", out
  end
end
