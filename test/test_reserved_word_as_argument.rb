# frozen_string_literal: true

require_relative 'test_helper'

# Reserved words (if, then, fi, ...) are only keywords in command position;
# as arguments they are ordinary words.
class TestReservedWordAsArgument < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def tokenize(input)
    Rubish::Lexer.new(input).tokenize
  end

  def test_reserved_words_as_arguments_lex_as_words
    %w[if then else elif fi while until for case esac select time function coproc def unless].each do |word|
      tokens = tokenize("echo #{word}")
      assert_equal [:WORD, :WORD], tokens.map(&:type), "echo #{word}"
    end
  end

  def test_echo_reserved_word_prints_it
    out = capture_stdout { execute('echo if then fi') }
    assert_equal "if then fi\n", out
  end

  def test_elif_as_argument_does_not_start_a_branch
    out = capture_stdout { execute('if false; then echo f; elif true; then echo elif; fi') }
    assert_equal "elif\n", out
  end

  def test_reserved_word_after_semicolon_is_still_a_keyword
    out = capture_stdout { execute('echo a; if true; then echo b; fi') }
    assert_equal "a\nb\n", out
  end

  def test_reserved_word_after_and_is_still_a_keyword
    out = capture_stdout { execute('true && if true; then echo y; fi') }
    assert_equal "y\n", out
  end

  def test_reserved_word_after_pipe_is_still_a_keyword
    # The loop runs in a forked child, so capture via a file
    Dir.mktmpdir('rubish_reserved_word') do |dir|
      out = File.join(dir, 'out.txt')
      execute(%(printf "1\\n2\\n" | while read l; do echo "<$l>"; done > #{out}))
      assert_equal "<1>\n<2>\n", File.read(out)
    end
  end

  def test_ruby_style_case_when_still_lexes_when_as_keyword
    tokens = tokenize('case foo when foo; echo yes; end')
    assert_equal :WHEN, tokens[2].type
  end

  def test_select_after_dot_still_lexes_as_keyword
    tokens = tokenize('seq(1, 6).select { it.to_i.even? }')
    assert_includes tokens.map(&:type), :SELECT
  end

  def test_then_after_test_brackets_is_a_keyword
    out = capture_stdout { execute('if [ 1 = 1 ]; then echo t; fi') }
    assert_equal "t\n", out
  end

  def test_fi_as_variable_value
    execute('fi=1')
    out = capture_stdout { execute('echo "$fi"') }
    assert_equal "1\n", out
  end
end
