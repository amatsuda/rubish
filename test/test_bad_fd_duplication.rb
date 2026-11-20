# frozen_string_literal: true

require_relative 'test_helper'

# >&N / 2>&N / <&N with an fd that is not open is an error, never a file named N
class TestBadFdDuplication < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @dir = Dir.mktmpdir('rubish_bad_fd')
    @original_dir = Dir.pwd
    Dir.chdir(@dir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@dir)
  end

  def test_stdout_to_unopened_fd_reports_bad_fd_and_creates_no_file
    err = capture_stderr { execute('echo ok >&3') }
    assert_match(/3: Bad file descriptor/, err)
    assert_false File.exist?('3'), 'must not create a file named 3'
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_stderr_to_unopened_fd_reports_bad_fd
    err = capture_stderr { execute('echo ok 2>&7') }
    assert_match(/7: Bad file descriptor/, err)
    assert_false File.exist?('7')
  end

  def test_stdin_from_unopened_fd_reports_bad_fd
    err = capture_stderr { execute('cat <&5') }
    assert_match(/5: Bad file descriptor/, err)
  end

  def test_known_fds_still_work
    execute('echo plain >&1 > out.txt')
    assert_equal "plain\n", File.read('out.txt')
    execute('echo also 2>&1 > out2.txt')
    assert_equal "also\n", File.read('out2.txt')
  end
end
