# frozen_string_literal: true

require_relative 'test_helper'

# When a builtin's redirection cannot be set up, the builtin does not run and
# the command fails, on every dispatch path
class TestFailedRedirectSkipsBuiltin < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_dir = Dir.pwd
  end

  def teardown
    Dir.chdir(@original_dir)
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  def test_process_builtin_with_unopenable_redirect_does_not_run
    out = capture_output { execute('cd /tmp > /no/such/dir/file_xyz') }
    assert_equal @original_dir, Dir.pwd
    assert_not_equal 0, last_status
    assert_match(/No such file/, out)
  end

  def test_process_builtin_in_list_with_unopenable_redirect_does_not_run
    capture_output { execute('true; cd /tmp > /no/such/dir/file_xyz') }
    assert_equal @original_dir, Dir.pwd
    assert_not_equal 0, last_status
  end

  def test_builtin_with_bad_fd_duplication_does_not_run
    out = capture_output { execute('echo leaked >&9') }
    assert_no_match(/leaked/, out)
    assert_equal 1, last_status
  end

  def test_builtin_with_unopenable_input_redirect_does_not_run
    out = capture_output { execute('echo hi < /no/such/file_xyz') }
    assert_no_match(/^hi$/, out)
    assert_not_equal 0, last_status
  end
end
