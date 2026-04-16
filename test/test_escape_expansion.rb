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
end
