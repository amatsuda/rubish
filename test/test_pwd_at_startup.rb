# frozen_string_literal: true

require_relative 'test_helper'

# A stale PWD in the environment is replaced by the real working directory
class TestPwdAtStartup < Test::Unit::TestCase
  def test_stale_pwd_is_corrected
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      real = File.realpath(dir)
      out = IO.popen({ 'PWD' => '/nonexistent/stale' }, [exe, '-c', 'echo "$PWD"', err: File::NULL], chdir: real, &:read)
      assert_equal "#{real}\n", out
    end
  end

  def test_pwd_naming_the_same_directory_is_kept
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      real = File.realpath(dir)
      File.symlink(real, "#{dir}/link") rescue nil
      link = "#{real}/link"
      out = IO.popen({ 'PWD' => link }, [exe, '-c', 'echo "$PWD"', err: File::NULL], chdir: real, &:read)
      assert_equal "#{link}\n", out
    end
  end
end
