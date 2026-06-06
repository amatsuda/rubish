# frozen_string_literal: true

require_relative 'test_helper'

# Integration tests for backslash-escape handling in unquoted shell words.
# In shell, \X in unquoted context means literal X (the backslash is removed).
# This allows filenames containing spaces or other special chars to be used
# as a single argument, e.g. `rm a\ b` removes the file named "a b".
class TestEscapeExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_escape_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # End-to-end: create file with space, remove via escaped-space syntax

  def test_rm_file_with_escaped_space
    FileUtils.touch(File.join(@tempdir, 'a b'))
    assert File.exist?(File.join(@tempdir, 'a b'))

    execute('rm a\\ b')

    refute File.exist?(File.join(@tempdir, 'a b'))
  end

  def test_cat_file_with_escaped_space
    File.write(File.join(@tempdir, 'hello world.txt'), "greetings\n")

    execute("cat hello\\ world.txt > #{output_file}")

    assert_equal "greetings\n", File.read(output_file)
  end

  def test_ls_file_with_multiple_escaped_spaces
    FileUtils.touch(File.join(@tempdir, 'a b c'))

    execute("ls a\\ b\\ c > #{output_file}")

    assert_match(/a b c/, File.read(output_file))
  end

  # echo tests: verify the argument passed to the command has no backslash

  def test_echo_escaped_space_produces_space
    execute("echo a\\ b > #{output_file}")
    assert_equal "a b\n", File.read(output_file)
  end

  def test_echo_escaped_dollar_is_literal
    ENV['TESTVAR'] = 'expanded'
    begin
      execute("echo \\$TESTVAR > #{output_file}")
      assert_equal "$TESTVAR\n", File.read(output_file)
    ensure
      ENV.delete('TESTVAR')
    end
  end

  def test_echo_escaped_backtick_is_literal
    execute("echo \\`date\\` > #{output_file}")
    assert_equal "`date`\n", File.read(output_file)
  end

  # \" in an unquoted word is a literal double quote (backslash removed), not a
  # quote delimiter. Regression: WordSegments treated the escaped " as a string
  # boundary, so `echo \"hi\"` produced `\hi"` instead of `"hi"`.
  def test_echo_escaped_double_quote_is_literal
    execute("echo \\\"hi\\\" > #{output_file}")
    assert_equal "\"hi\"\n", File.read(output_file)
  end

  def test_echo_escaped_double_quote_midword
    execute("echo a\\\"b > #{output_file}")
    assert_equal "a\"b\n", File.read(output_file)
  end

  def test_echo_escaped_single_quote_is_literal
    execute("echo \\'hi\\' > #{output_file}")
    assert_equal "'hi'\n", File.read(output_file)
  end

  # The read builtin's bash-suite tests print results with `echo \"$x.\"`; the
  # escaped-quote bug made every one of them fail. Cover that exact shape.
  def test_read_then_echo_escaped_quotes
    execute("echo ' a ' | (read x; echo \\\"$x.\\\") > #{output_file}")
    assert_equal "\"a.\"\n", File.read(output_file)
  end

  def test_echo_escaped_backslash_produces_backslash
    execute("echo a\\\\b > #{output_file}")
    assert_equal "a\\b\n", File.read(output_file)
  end

  def test_echo_mixed_escape_and_variable
    ENV['GREETING'] = 'hi'
    begin
      # \ before space is escaped, $GREETING still expands
      execute("echo a\\ $GREETING > #{output_file}")
      assert_equal "a hi\n", File.read(output_file)
    ensure
      ENV.delete('GREETING')
    end
  end

  # Quoted context behavior (unchanged by the fix)

  def test_single_quoted_backslash_is_literal
    execute("echo 'a\\ b' > #{output_file}")
    assert_equal "a\\ b\n", File.read(output_file)
  end

  def test_double_quoted_escaped_dollar_is_literal
    ENV['TESTVAR'] = 'expanded'
    begin
      execute("echo \"\\$TESTVAR\" > #{output_file}")
      assert_equal "$TESTVAR\n", File.read(output_file)
    ensure
      ENV.delete('TESTVAR')
    end
  end

  def test_double_quoted_backslash_before_non_special_is_preserved
    # In double quotes, \z is not a recognized escape, so both chars are kept
    execute('echo "a\\zb" > ' + output_file)
    assert_equal "a\\zb\n", File.read(output_file)
  end

  # The cd / pushd builtins go through a fast path that bypasses
  # codegen (repl.rb:1000), so escape-handling has to happen in
  # expand_args_for_builtin. Without that, `cd ab\ cd/` reaches
  # chdir as a literal `ab\ cd/` path and fails.
  def test_cd_into_directory_with_escaped_space
    FileUtils.mkdir(File.join(@tempdir, 'Foo Bar'))

    execute('cd Foo\\ Bar')

    assert_equal File.realpath(File.join(@tempdir, 'Foo Bar')), File.realpath(Dir.pwd)
  end

  def test_cd_into_directory_with_escaped_space_and_trailing_slash
    FileUtils.mkdir(File.join(@tempdir, 'ab cd'))

    execute('cd ab\\ cd/')

    assert_equal File.realpath(File.join(@tempdir, 'ab cd')), File.realpath(Dir.pwd)
  end

  def test_pushd_into_directory_with_escaped_space
    FileUtils.mkdir(File.join(@tempdir, 'Foo Bar'))

    execute('pushd Foo\\ Bar')

    assert_equal File.realpath(File.join(@tempdir, 'Foo Bar')), File.realpath(Dir.pwd)
  end

  # Adjacent quoted segments are concatenated into one word (bash/POSIX behavior).
  # eg. 'foo''bar' is two adjacent single-quoted tokens forming the word "foobar".

  def test_adjacent_single_quoted_segments_concatenate
    execute("echo 'two single-quoted pa''rts in one token' > #{output_file}")
    assert_equal "two single-quoted parts in one token\n", File.read(output_file)
  end

  def test_unquoted_adjacent_to_single_quoted_concatenates
    execute("echo unquoted' and single-quoted' > #{output_file}")
    assert_equal "unquoted and single-quoted\n", File.read(output_file)
  end

  def test_mixed_quote_styles_in_one_word_concatenate
    execute("echo unquoted'  single-quoted'\"  double-quoted  \"unquoted > #{output_file}")
    assert_equal "unquoted  single-quoted  double-quoted  unquoted\n", File.read(output_file)
  end

  # A "$(...)"/`...` segment that itself contains " must not end the double-quoted
  # segment early when the token has adjacent segments (the cmdsub must still run).
  def test_double_quoted_command_substitution_with_inner_quotes_in_multi_segment_word
    execute('echo "$(printf "%s" hi)"_tail > ' + output_file)
    assert_equal "hi_tail\n", File.read(output_file)
  end

  def test_double_quoted_backtick_with_inner_quotes_in_multi_segment_word
    execute('echo "`echo "x"`"_tail > ' + output_file)
    assert_equal "x_tail\n", File.read(output_file)
  end
end
