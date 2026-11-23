# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# When the current directory has been removed, cd still works and pwd
# reports the problem instead of crashing
class TestRemovedWorkingDirectory < Test::Unit::TestCase
  def run_shell(script, dir)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w, chdir: dir], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_cd_to_an_absolute_path_after_the_cwd_is_removed
    Dir.mktmpdir do |base|
      out, err = run_shell('mkdir d; cd d; rmdir ../d; cd /; echo "ok $PWD"', base)
      assert_equal "ok /\n", out
      assert_equal '', err
    end
  end

  def test_pwd_reports_the_missing_directory
    Dir.mktmpdir do |base|
      out, err = run_shell('mkdir d; cd d; rmdir ../d; pwd -P; echo "status $?"', base)
      assert_equal "status 1\n", out
      assert_match(/pwd: error retrieving current directory/, err)
      assert_no_match(/Errno|\.rb:\d+/, err)
    end
  end
end
