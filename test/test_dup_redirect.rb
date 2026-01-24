# frozen_string_literal: true

require_relative 'test_helper'

# Tests for file descriptor duplication redirects: >&N, <&N
class TestDupRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_dup_redirect_test')
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

  def stderr_file
    File.join(@tempdir, 'stderr.txt')
  end

  # Test >&2 - redirect stdout to stderr
  def test_dup_stdout_to_stderr
    # Redirect stderr to a file, then use >&2 to send stdout there
    execute("echo 'to stderr' >&2 2>#{stderr_file}")
    assert_equal "to stderr\n", File.read(stderr_file)
  end

  def test_dup_stdout_to_stderr_no_stdout_output
    # With >&2, nothing should go to stdout
    execute("echo 'test' >&2 >#{output_file} 2>/dev/null")
    # stdout file should be empty since echo output went to stderr
    assert_equal '', File.read(output_file)
  end

  # Test >&1 - no-op (stdout to stdout)
  def test_dup_stdout_to_stdout_noop
    execute("echo 'normal' >&1 >#{output_file}")
    assert_equal "normal\n", File.read(output_file)
  end

  # Test that regular redirects still work
  def test_regular_stdout_redirect
    execute("echo 'hello' >#{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_regular_stderr_redirect
    execute("echo 'error' >&2 2>#{stderr_file}")
    assert_equal "error\n", File.read(stderr_file)
  end

  # Test lexer recognizes >& operator
  def test_lexer_recognizes_dup_output_redirect
    lexer = Rubish::Lexer.new('echo test >&2')
    tokens = lexer.tokenize

    redirect_token = tokens.find { |t| t.type == :REDIRECT && t.value == '>&' }
    assert_not_nil redirect_token, 'Lexer should recognize >&'
  end

  def test_lexer_recognizes_dup_input_redirect
    lexer = Rubish::Lexer.new('cat <&3')
    tokens = lexer.tokenize

    redirect_token = tokens.find { |t| t.type == :REDIRECT && t.value == '<&' }
    assert_not_nil redirect_token, 'Lexer should recognize <&'
  end
end
