# frozen_string_literal: true

require_relative 'test_helper'

# printf %q quotes like bash: backslash-escapes for printable text, and the
# $'...' form only when the string has non-printing characters
class TestPrintfQStyle < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def q(arg)
    capture_stdout { Rubish::Builtins.run('printf', ['%q\n', arg]) }.chomp
  end

  def test_plain_word_is_unchanged
    assert_equal 'plain', q('plain')
  end

  def test_spaces_and_quotes_are_backslash_escaped
    assert_equal %q(a\ b\'c), q("a b'c")
    assert_equal %q(say\ \"hi\"), q('say "hi"')
  end

  def test_shell_metacharacters_are_escaped
    assert_equal %q(\$HOME\;\ ls\ \*), q('$HOME; ls *')
  end

  def test_non_printing_characters_use_ansi_c_quoting
    assert_equal %q($'a\tb'), q("a\tb")
    assert_equal %q($'line\n'), q("line\n")
  end

  def test_empty_string_is_two_single_quotes
    assert_equal "''", q('')
  end
end
