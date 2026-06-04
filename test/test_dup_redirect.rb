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

  # `2>>file` used to be lexed as REDIRECT_ERR + REDIRECT_OUT + WORD,
  # so it silently truncated and *redirected stdout* to the file rather
  # than appending stderr.
  def test_redirect_err_append
    log = File.join(@tempdir, 'log')
    execute("/bin/ls /no/such/A 2>>#{log}")
    execute("/bin/ls /no/such/B 2>>#{log}")
    content = File.read(log)
    assert_match(/A/, content)
    assert_match(/B/, content)
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

  # A digit immediately followed by an output (1) or input (0) redirect
  # operator is a verbose alias for the bare form. The leading digit
  # used to be lexed as a standalone WORD, so e.g. `echo hi 1>file`
  # wrote `hi 1` to the file.
  def test_fd1_prefix_redirect_out
    out = File.join(@tempdir, 'out')
    execute("echo hi 1>#{out}")
    assert_equal "hi\n", File.read(out)
  end

  def test_fd1_prefix_redirect_append
    out = File.join(@tempdir, 'out')
    execute("echo a 1>#{out}")
    execute("echo b 1>>#{out}")
    assert_equal "a\nb\n", File.read(out)
  end

  def test_fd1_prefix_dup
    # `1>&2` is a verbose `>&2` — redirect stdout to stderr.
    # The leading `1` must be consumed as an fd prefix, not surface as
    # an argument to echo. Check via the AST since DUP_OUT's target
    # (the `2`) is also a WORD token at lex time.
    tokens = Rubish::Lexer.new('echo hi 1>&2').tokenize
    ast = Rubish::Parser.new(tokens).parse
    cmd = ast.is_a?(Rubish::AST::Redirect) ? ast.command : ast
    assert_equal 'echo', cmd.name
    assert_equal %w[hi], cmd.args
  end

  def test_fd0_prefix_redirect_in
    src = File.join(@tempdir, 'in')
    out = File.join(@tempdir, 'out')
    File.write(src, "hello\n")
    execute("cat 0<#{src} > #{out}")
    assert_equal "hello\n", File.read(out)
  end

  # `echo 1 >file` (whitespace between digit and redirect) still puts
  # "1" in the file.
  def test_digit_with_whitespace_before_redirect_is_arg
    out = File.join(@tempdir, 'out')
    execute("echo 1 >#{out}")
    assert_equal "1\n", File.read(out)
  end

  # Numbers that aren't followed immediately by a redirect operator
  # stay as plain WORDs.
  def test_digit_not_followed_by_redirect_stays_a_word
    out = File.join(@tempdir, 'out')
    execute("echo 1abc 0xyz >#{out}")
    assert_equal "1abc 0xyz\n", File.read(out)
  end

  # Arbitrary fds (>= 3) used to be lexed as a free WORD followed by
  # the bare redirect — so `echo hi 3>file` wrote `hi 3` to the file
  # and stdout got redirected. Now the lexer emits an FD_REDIRECT
  # token carrying the source fd, and Command threads it through
  # Kernel#exec's redirect-options hash.
  def test_fd3_open_for_write
    out = File.join(@tempdir, 'out')
    # /bin/sh writes "X" to fd 3, which 3>file directs to the file.
    execute("/bin/sh -c 'printf X >&3' 3>#{out}")
    assert_equal 'X', File.read(out)
  end

  def test_fd3_append
    out = File.join(@tempdir, 'out')
    File.write(out, "a\n")
    execute("/bin/sh -c 'printf B >&3' 3>>#{out}")
    assert_equal "a\nB", File.read(out)
  end

  def test_fd3_open_for_read
    src = File.join(@tempdir, 'src')
    out = File.join(@tempdir, 'out')
    File.write(src, "fileinput\n")
    execute("/bin/sh -c 'read line <&3; echo $line' 3<#{src} > #{out}")
    assert_equal "fileinput\n", File.read(out)
  end

  def test_fd3_dup_to_stdout
    out = File.join(@tempdir, 'out')
    # 3>&1 dups stdout to fd 3, then the inner sh writes to fd 3,
    # which lands on the outer stdout (redirected to the file).
    execute("/bin/sh -c 'printf hello >&3' 3>&1 > #{out}")
    assert_equal 'hello', File.read(out)
  end

  # Multi-digit fds work too — the lexer doesn't cap the digit count.
  # Child is bash (rubish's compatibility target): POSIX sh/dash caps
  # redirection fds at one digit, so >&10 needs bash.
  def test_fd10_open_for_write
    out = File.join(@tempdir, 'out')
    execute("/usr/bin/env bash -c 'printf via10 >&10' 10>#{out}")
    assert_equal 'via10', File.read(out)
  end

  # An fd-redirect on a pipeline attaches to the command immediately
  # preceding the pipe.
  def test_fd3_on_pipeline_first_command
    out = File.join(@tempdir, 'out')
    execute("/bin/sh -c 'printf to-3 >&3' 3>#{out} | cat")
    assert_equal 'to-3', File.read(out)
  end
end
