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

  # Lexer used to split `2>&1` into [REDIRECT_ERR, AMPERSAND, WORD],
  # so rubish tried to run `1` as a separate command after the redirect.
  # `ls /no/such/dir 2>&1` reported the legitimate ls error and then
  # also `rubish: 1: command not found`.
  def test_lexer_recognizes_dup_err_redirect
    tokens = Rubish::Lexer.new('cmd 2>&1').tokenize
    assert_not_nil tokens.find { |t| t.type == :DUP_ERR },
                   'Lexer should recognize 2>& as DUP_ERR'
  end

  # Redirect through a file (not capture_*) because the merged stream
  # lives at fd-level, not Ruby's $stdout/$stderr.
  def test_2_to_amp_1_merges_stderr_into_stdout
    out = File.join(@tempdir, 'out.txt')
    execute("/bin/ls /no/such/dir_xyz > #{out} 2>&1")
    content = File.read(out)
    assert_match(/No such file or directory/, content)
    assert_no_match(/command not found/, content)
  end

  def test_2_to_amp_close_closes_stderr
    out = File.join(@tempdir, 'out.txt')
    execute("/bin/ls /no/such/dir_xyz > #{out} 2>&-")
    # stderr closed; the error message from ls is gone
    assert_equal '', File.read(out)
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

  # Test that redirecting input from a nonexistent file fails gracefully:
  # sets non-zero exit status and prints a shell error rather than raising a Ruby exception.
  def test_redirect_in_nonexistent_file
    stderr_output = capture_stderr do
      execute('cat < /nonexistent_file_rubish_test_xyz 2>/dev/null')
    end
    assert_not_equal 0, @repl.instance_variable_get(:@last_status)
    assert_match(/rubish:.*nonexistent_file/, stderr_output)
  end

  # Output redirect to a path whose parent dir doesn't exist used to raise
  # Errno::ENOENT with a Ruby backtrace. Now reports a shell error and
  # the command does not run. Uses /bin/cat (not a builtin) so the
  # Command fork-and-exec path is exercised — see follow-up commit for
  # the builtin fast-path bypass.
  def test_redirect_out_nonexistent_directory
    stderr_output = capture_stderr do
      execute('/bin/cat /etc/hostname > /no/such/dir/file_xyz')
    end
    assert_not_equal 0, @repl.instance_variable_get(:@last_status)
    assert_match(%r{rubish: /no/such/dir/file_xyz:.*No such file}, stderr_output)
  end

  def test_redirect_append_nonexistent_directory
    stderr_output = capture_stderr do
      execute('/bin/cat /etc/hostname >> /no/such/dir/file_xyz')
    end
    assert_not_equal 0, @repl.instance_variable_get(:@last_status)
    assert_match(%r{rubish: /no/such/dir/file_xyz:.*No such file}, stderr_output)
  end

  def test_redirect_err_nonexistent_directory
    stderr_output = capture_stderr do
      execute('/bin/cat /no/such/source 2> /no/such/dir/file_xyz')
    end
    assert_not_equal 0, @repl.instance_variable_get(:@last_status)
    assert_match(%r{rubish: /no/such/dir/file_xyz:.*No such file}, stderr_output)
  end

  def test_redirect_clobber_nonexistent_directory
    stderr_output = capture_stderr do
      execute('/bin/cat /etc/hostname >| /no/such/dir/file_xyz')
    end
    assert_not_equal 0, @repl.instance_variable_get(:@last_status)
    assert_match(%r{rubish: /no/such/dir/file_xyz:.*No such file}, stderr_output)
  end

  # Builtins go through __run_cmd's fast path which used to bypass
  # @restricted_failed — so `echo hi > /no/such/dir/file; echo $?` would
  # both print the error AND then run echo, leaving $? as 0. The
  # fast-path now checks restricted_failed / noclobber_failed.
  def test_builtin_skipped_when_output_redirect_fails
    stdout_output = nil
    stderr_output = capture_stderr do
      stdout_output = capture_stdout do
        execute('echo hi > /no/such/dir/file_xyz')
      end
    end
    assert_not_equal 0, @repl.instance_variable_get(:@last_status)
    assert_match(%r{rubish: /no/such/dir/file_xyz:.*No such file}, stderr_output)
    assert_empty stdout_output, 'echo must not run when its redirect target could not be opened'
  end

  def test_builtin_skipped_when_input_redirect_fails
    stdout_output = nil
    stderr_output = capture_stderr do
      stdout_output = capture_stdout do
        execute('echo hi < /no/such/file_xyz')
      end
    end
    assert_not_equal 0, @repl.instance_variable_get(:@last_status)
    assert_match(%r{rubish: /no/such/file_xyz:.*No such file}, stderr_output)
    assert_empty stdout_output
  end

  def test_builtin_skipped_when_noclobber_redirect_fails
    require 'tempfile'
    tf = Tempfile.create('rubish_noclobber')
    tf.close
    begin
      stdout_output = nil
      stderr_output = capture_stderr do
        stdout_output = capture_stdout do
          execute('set -C')
          execute("echo hi > #{tf.path}")
        end
      end
      assert_not_equal 0, @repl.instance_variable_get(:@last_status)
      assert_match(/cannot overwrite existing file/, stderr_output)
      assert_empty stdout_output
    ensure
      execute('set +C')
      File.unlink(tf.path) if File.exist?(tf.path)
    end
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
