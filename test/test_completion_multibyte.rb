# frozen_string_literal: true

require_relative 'test_helper'

class TestCompletionMultibyte < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_completion_mb_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    Rubish::Builtins.clear_completions
    Rubish::Builtins.setup_default_completions
  end

  def teardown
    Rubish::Builtins.clear_completions
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Simulate calling complete() with a given line, byte-based cursor position, and input word.
  # Reline.point returns byte_pointer, so we stub both Reline.line_buffer and Reline.point.
  def complete_with(line, byte_point, input)
    original_line_buffer = Reline.method(:line_buffer)
    original_point = Reline.method(:point)

    verbose = $VERBOSE
    $VERBOSE = nil
    Reline.define_singleton_method(:line_buffer) { line }
    Reline.define_singleton_method(:point) { byte_point }
    $VERBOSE = verbose

    @repl.send(:complete, input)
  ensure
    $VERBOSE = nil
    Reline.define_singleton_method(:line_buffer, original_line_buffer)
    Reline.define_singleton_method(:point, original_point)
    $VERBOSE = verbose
  end

  # ==========================================================================
  # Byte-to-character offset conversion
  # ==========================================================================

  def test_complete_does_not_crash_with_multibyte_arg
    # "echo あ" — 6 chars, 8 bytes (あ = 3 bytes in UTF-8)
    line = 'echo あ'
    assert_equal 6, line.length
    assert_equal 8, line.bytesize

    # Should not raise TypeError: no implicit conversion of nil into String
    assert_nothing_raised { complete_with(line, line.bytesize, 'あ') }
  end

  def test_complete_does_not_crash_with_multibyte_command
    # "あいう" — 3 chars, 9 bytes
    line = 'あいう'
    assert_nothing_raised { complete_with(line, line.bytesize, 'あいう') }
  end

  def test_complete_does_not_crash_with_multibyte_before_cursor
    # Cursor after space: "あ " — 2 chars, 4 bytes
    line = 'あ '
    assert_nothing_raised { complete_with(line, line.bytesize, '') }
  end

  def test_complete_does_not_crash_with_mixed_ascii_and_multibyte
    # "echo あ い" — 8 chars, 12 bytes
    line = 'echo あ い'
    assert_nothing_raised { complete_with(line, line.bytesize, 'い') }
  end

  def test_complete_does_not_crash_with_cursor_mid_line_after_multibyte
    # Cursor in the middle: "あ echo foo" with cursor at the end of "echo "
    # "あ echo " is 6 chars, 8 bytes
    line = 'あ echo foo'
    byte_point = 'あ echo '.bytesize  # 8
    assert_nothing_raised { complete_with(line, byte_point, '') }
  end

  def test_complete_does_not_crash_with_emoji
    # Emoji can be 4 bytes in UTF-8
    line = 'echo 🍣'
    assert_nothing_raised { complete_with(line, line.bytesize, '🍣') }
  end

  # ==========================================================================
  # Correct word splitting with multibyte characters
  # ==========================================================================

  def test_complete_identifies_first_word_correctly_with_multibyte
    # Single multibyte word should be treated as command (first word)
    line = 'あ'
    result = complete_with(line, line.bytesize, 'あ')
    # Should not crash; result is an array of completions
    assert_kind_of Array, result
  end

  def test_complete_identifies_arg_correctly_after_multibyte_command
    # "あ foo" — completing 'foo' after a multibyte command
    line = 'あ foo'
    result = complete_with(line, line.bytesize, 'foo')
    assert_kind_of Array, result
  end

  # ==========================================================================
  # calculate_comp_cword with multibyte
  # ==========================================================================

  def test_calculate_comp_cword_with_multibyte_words
    line = 'echo あ い'
    words = %w[echo あ い]
    # point is now in character units (after the fix)
    point = line.length  # 8 chars, cursor at end

    cword = @repl.send(:calculate_comp_cword, line, point, words)
    # Cursor is at/after the last word
    assert_equal 2, cword
  end

  def test_calculate_comp_cword_cursor_on_first_multibyte_word
    line = 'あ い'
    words = %w[あ い]
    point = 1  # character position of あ (end of first word)

    cword = @repl.send(:calculate_comp_cword, line, point, words)
    assert_equal 0, cword
  end

  def test_calculate_comp_cword_cursor_on_second_word_after_multibyte
    line = 'あ test'
    words = %w[あ test]
    point = 'あ te'.length  # 4 chars, cursor mid-second word

    cword = @repl.send(:calculate_comp_cword, line, point, words)
    assert_equal 1, cword
  end

  # ==========================================================================
  # split_completion_words with multibyte
  # ==========================================================================

  def test_split_completion_words_with_multibyte
    words = @repl.send(:split_completion_words, 'echo あ い')
    assert_equal %w[echo あ い], words
  end

  def test_split_completion_words_multibyte_command
    words = @repl.send(:split_completion_words, 'あ --flag')
    assert_equal %w[あ --flag], words
  end

  def test_split_completion_words_multibyte_only
    words = @repl.send(:split_completion_words, 'あ い う')
    assert_equal %w[あ い う], words
  end
end
