# frozen_string_literal: true

require_relative 'test_helper'

# Symbolic fd redirections (2>&1, >&2, 2>&-) on a command inside a pipeline
class TestPipelineFdRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_pipeline_fd_redirect')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
  end

  def output
    File.read(File.join(@tempdir, 'out.txt'))
  end

  def test_stderr_to_stdout_in_pipeline_merges_stderr_into_pipe
    execute('ls /nonexistent_rubish_dir 2>&1 | cat > out.txt')
    assert_match(/No such file/, output)
  end

  def test_stderr_to_stdout_in_pipeline_keeps_stdout_flowing
    execute('/bin/echo hello 2>&1 | cat > out.txt')
    assert_equal "hello\n", output
  end

  def test_stderr_to_stdout_in_pipeline_sets_pipeline_status
    execute('/bin/echo hello 2>&1 | cat > out.txt')
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_stdout_to_stderr_in_pipeline_bypasses_pipe
    execute('/bin/echo hello >&2 2>/dev/null | cat > out.txt')
    assert_equal '', output
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_closed_stderr_in_pipeline_does_not_crash
    execute('/bin/echo hello 2>&- | cat > out.txt')
    assert_equal "hello\n", output
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end
end
