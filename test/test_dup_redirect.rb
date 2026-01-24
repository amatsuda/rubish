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

  # Test that Command has dup_out method
  def test_command_has_dup_out_method
    cmd = Rubish::Command.new('echo', 'test')
    assert cmd.respond_to?(:dup_out), 'Command should have dup_out method'
  end

  def test_command_has_dup_in_method
    cmd = Rubish::Command.new('echo', 'test')
    assert cmd.respond_to?(:dup_in), 'Command should have dup_in method'
  end

  # Test dup_out returns self for chaining
  def test_dup_out_returns_self
    cmd = Rubish::Command.new('echo', 'test')
    result = cmd.dup_out('2')
    assert_same cmd, result, 'dup_out should return self for chaining'
  end

  def test_dup_in_returns_self
    cmd = Rubish::Command.new('echo', 'test')
    result = cmd.dup_in('0')
    assert_same cmd, result, 'dup_in should return self for chaining'
  end

  # Test lexer recognizes >& operator
  def test_lexer_recognizes_dup_output_redirect
    lexer = Rubish::Lexer.new('echo test >&2')
    tokens = lexer.tokenize

    redirect_token = tokens.find { |t| t.type == :DUP_OUT }
    assert_not_nil redirect_token, 'Lexer should recognize >& as DUP_OUT'
  end

  def test_lexer_recognizes_dup_input_redirect
    lexer = Rubish::Lexer.new('cat <&3')
    tokens = lexer.tokenize

    redirect_token = tokens.find { |t| t.type == :DUP_IN }
    assert_not_nil redirect_token, 'Lexer should recognize <& as DUP_IN'
  end

  # Test that >&2 doesn't cause errors (regression test)
  # Previously this would fail with: undefined method 'dup_out' for Command
  def test_dup_stdout_to_stderr_no_error
    # This should not raise an error
    assert_nothing_raised do
      execute('echo "test" >&2')
    end
  end

  # Test Pipeline has dup_out/dup_in methods
  def test_pipeline_has_dup_out_method
    cmd1 = Rubish::Command.new('echo', 'test')
    cmd2 = Rubish::Command.new('cat')
    pipeline = Rubish::Pipeline.new(cmd1, cmd2)
    assert pipeline.respond_to?(:dup_out), 'Pipeline should have dup_out method'
  end

  def test_pipeline_has_dup_in_method
    cmd1 = Rubish::Command.new('echo', 'test')
    cmd2 = Rubish::Command.new('cat')
    pipeline = Rubish::Pipeline.new(cmd1, cmd2)
    assert pipeline.respond_to?(:dup_in), 'Pipeline should have dup_in method'
  end

  # Test Subshell has dup_out/dup_in methods
  def test_subshell_has_dup_out_method
    subshell = Rubish::Subshell.new { true }
    assert subshell.respond_to?(:dup_out), 'Subshell should have dup_out method'
  end

  def test_subshell_has_dup_in_method
    subshell = Rubish::Subshell.new { true }
    assert subshell.respond_to?(:dup_in), 'Subshell should have dup_in method'
  end
end
