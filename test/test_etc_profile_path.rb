# frozen_string_literal: true

require_relative 'test_helper'

# A login shell on macOS takes its PATH from /etc/profile, whose
# `eval `/usr/libexec/path_helper -s`` must leave exactly what path_helper
# says, as in bash
class TestEtcProfilePath < Test::Unit::TestCase
  PATH_HELPER = '/usr/libexec/path_helper'

  def setup
    omit 'needs macOS path_helper and /etc/profile' unless File.executable?(PATH_HELPER) && File.exist?('/etc/profile')
    @original_env = ENV.to_h
    @tempdir = Dir.mktmpdir('rubish_etc_profile')
    ENV['HOME'] = @tempdir
    ENV.delete('XDG_CONFIG_HOME')
  end

  def teardown
    return unless @original_env
    ENV.replace(@original_env)
    FileUtils.rm_rf(@tempdir)
  end

  def test_login_profile_sets_path_helpers_path
    ENV['PATH'] = '/bin'
    expected = IO.popen({'PATH' => '/bin'}, [PATH_HELPER, '-s'], &:read)[/\APATH="([^"]*)"/, 1]
    repl = Rubish::REPL.new(login_shell: true)
    repl.send(:load_login_config)
    assert_equal expected, ENV['PATH']
  end
end
