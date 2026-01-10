# frozen_string_literal: true

require_relative 'test_helper'

class TestStartupFiles < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @original_home = ENV['HOME']
    @tempdir = Dir.mktmpdir('rubish_startup_test')
    ENV['HOME'] = @tempdir
    # Reset shell options
    Rubish::Builtins.set_shell_option('login_shell', false)
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    ENV['HOME'] = @original_home
    FileUtils.rm_rf(@tempdir)
  end

  # Helper to create a REPL that skips system profile files
  # System files like /etc/profile may contain complex bash syntax
  def create_test_repl(login_shell: false, no_profile: false, no_rc: false)
    repl = Rubish::REPL.new(login_shell: login_shell, no_profile: no_profile, no_rc: no_rc)
    # Override the load methods to skip system files for testing
    def repl.load_login_config
      return if @no_profile
      # Skip /etc/profile - only load user files
      profile_files = [
        File.expand_path('~/.bash_profile'),
        File.expand_path('~/.bash_login'),
        File.expand_path('~/.profile')
      ]
      profile_files.each do |profile|
        if File.exist?(profile)
          source_if_exists(profile)
          break
        end
      end
      source_if_exists(File.expand_path('~/.rubish_profile'))
    end

    def repl.load_interactive_config
      return if @no_rc
      # Skip system bashrc files for testing
      source_if_exists(File.expand_path('~/.bashrc'))
      source_if_exists(File.expand_path('~/.rubishrc'))
      env_file = ENV['ENV']
      if env_file && !env_file.empty?
        source_if_exists(File.expand_path(env_file))
      end
    end
    repl
  end

  # ==========================================================================
  # Login shell tests
  # ==========================================================================

  def test_login_shell_flag_sets_shopt
    repl = create_test_repl(login_shell: true)
    assert Rubish::Builtins.shopt_enabled?('login_shell')
  end

  def test_non_login_shell_shopt_is_false
    repl = create_test_repl(login_shell: false)
    assert_false Rubish::Builtins.shopt_enabled?('login_shell')
  end

  def test_login_shell_sources_profile
    # Create a .profile file
    File.write(File.join(@tempdir, '.profile'), 'PROFILE_SOURCED=yes')

    repl = create_test_repl(login_shell: true)
    # Manually call load_config since run() would start the REPL loop
    repl.send(:load_config)

    assert_equal 'yes', ENV['PROFILE_SOURCED']
  end

  def test_login_shell_sources_bash_profile_first
    # Create both .bash_profile and .profile
    File.write(File.join(@tempdir, '.bash_profile'), 'BASH_PROFILE_SOURCED=yes')
    File.write(File.join(@tempdir, '.profile'), 'PROFILE_SOURCED=yes')

    repl = create_test_repl(login_shell: true)
    repl.send(:load_config)

    # .bash_profile should be sourced, not .profile
    assert_equal 'yes', ENV['BASH_PROFILE_SOURCED']
    assert_nil ENV['PROFILE_SOURCED']
  end

  def test_login_shell_sources_bash_login_if_no_bash_profile
    # Create .bash_login and .profile (no .bash_profile)
    File.write(File.join(@tempdir, '.bash_login'), 'BASH_LOGIN_SOURCED=yes')
    File.write(File.join(@tempdir, '.profile'), 'PROFILE_SOURCED=yes')

    repl = create_test_repl(login_shell: true)
    repl.send(:load_config)

    # .bash_login should be sourced, not .profile
    assert_equal 'yes', ENV['BASH_LOGIN_SOURCED']
    assert_nil ENV['PROFILE_SOURCED']
  end

  def test_login_shell_sources_rubish_profile
    # Create .rubish_profile
    File.write(File.join(@tempdir, '.rubish_profile'), 'RUBISH_PROFILE_SOURCED=yes')

    repl = create_test_repl(login_shell: true)
    repl.send(:load_config)

    assert_equal 'yes', ENV['RUBISH_PROFILE_SOURCED']
  end

  def test_login_shell_sources_both_bash_profile_and_rubish_profile
    # Create both
    File.write(File.join(@tempdir, '.bash_profile'), 'BASH_PROFILE_SOURCED=yes')
    File.write(File.join(@tempdir, '.rubish_profile'), 'RUBISH_PROFILE_SOURCED=yes')

    repl = create_test_repl(login_shell: true)
    repl.send(:load_config)

    # Both should be sourced
    assert_equal 'yes', ENV['BASH_PROFILE_SOURCED']
    assert_equal 'yes', ENV['RUBISH_PROFILE_SOURCED']
  end

  def test_noprofile_skips_profile_files
    File.write(File.join(@tempdir, '.profile'), 'PROFILE_SOURCED=yes')

    repl = create_test_repl(login_shell: true, no_profile: true)
    repl.send(:load_config)

    assert_nil ENV['PROFILE_SOURCED']
  end

  # ==========================================================================
  # Non-login shell tests
  # ==========================================================================

  def test_non_login_shell_sources_bashrc
    File.write(File.join(@tempdir, '.bashrc'), 'BASHRC_SOURCED=yes')

    repl = create_test_repl(login_shell: false)
    repl.send(:load_config)

    assert_equal 'yes', ENV['BASHRC_SOURCED']
  end

  def test_non_login_shell_sources_rubishrc
    File.write(File.join(@tempdir, '.rubishrc'), 'RUBISHRC_SOURCED=yes')

    repl = create_test_repl(login_shell: false)
    repl.send(:load_config)

    assert_equal 'yes', ENV['RUBISHRC_SOURCED']
  end

  def test_non_login_shell_sources_both_bashrc_and_rubishrc
    File.write(File.join(@tempdir, '.bashrc'), 'BASHRC_SOURCED=yes')
    File.write(File.join(@tempdir, '.rubishrc'), 'RUBISHRC_SOURCED=yes')

    repl = create_test_repl(login_shell: false)
    repl.send(:load_config)

    assert_equal 'yes', ENV['BASHRC_SOURCED']
    assert_equal 'yes', ENV['RUBISHRC_SOURCED']
  end

  def test_non_login_shell_does_not_source_profile
    File.write(File.join(@tempdir, '.profile'), 'PROFILE_SOURCED=yes')
    File.write(File.join(@tempdir, '.bash_profile'), 'BASH_PROFILE_SOURCED=yes')

    repl = create_test_repl(login_shell: false)
    repl.send(:load_config)

    # Profile files should not be sourced for non-login shells
    assert_nil ENV['PROFILE_SOURCED']
    assert_nil ENV['BASH_PROFILE_SOURCED']
  end

  def test_norc_skips_rc_files
    File.write(File.join(@tempdir, '.bashrc'), 'BASHRC_SOURCED=yes')
    File.write(File.join(@tempdir, '.rubishrc'), 'RUBISHRC_SOURCED=yes')

    repl = create_test_repl(login_shell: false, no_rc: true)
    repl.send(:load_config)

    assert_nil ENV['BASHRC_SOURCED']
    assert_nil ENV['RUBISHRC_SOURCED']
  end

  # ==========================================================================
  # ENV variable tests
  # ==========================================================================

  def test_env_file_sourced_in_non_login_shell
    env_file = File.join(@tempdir, 'my_env')
    File.write(env_file, 'ENV_FILE_SOURCED=yes')
    ENV['ENV'] = env_file

    repl = create_test_repl(login_shell: false)
    repl.send(:load_config)

    assert_equal 'yes', ENV['ENV_FILE_SOURCED']
  end

  # ==========================================================================
  # Privileged mode tests
  # ==========================================================================

  def test_privileged_mode_skips_all_startup_files
    File.write(File.join(@tempdir, '.profile'), 'PROFILE_SOURCED=yes')
    File.write(File.join(@tempdir, '.bashrc'), 'BASHRC_SOURCED=yes')

    # Enable privileged mode
    Rubish::Builtins.instance_variable_get(:@set_options)['p'] = true

    begin
      repl = create_test_repl(login_shell: true)
      repl.send(:load_config)

      assert_nil ENV['PROFILE_SOURCED']
      assert_nil ENV['BASHRC_SOURCED']
    ensure
      Rubish::Builtins.instance_variable_get(:@set_options)['p'] = false
    end
  end

  # ==========================================================================
  # Logout file tests
  # ==========================================================================

  def test_login_shell_sources_bash_logout
    File.write(File.join(@tempdir, '.bash_logout'), 'BASH_LOGOUT_SOURCED=yes')

    repl = create_test_repl(login_shell: true)
    repl.send(:load_logout_config)

    assert_equal 'yes', ENV['BASH_LOGOUT_SOURCED']
  end

  def test_login_shell_sources_rubish_logout
    File.write(File.join(@tempdir, '.rubish_logout'), 'RUBISH_LOGOUT_SOURCED=yes')

    repl = create_test_repl(login_shell: true)
    repl.send(:load_logout_config)

    assert_equal 'yes', ENV['RUBISH_LOGOUT_SOURCED']
  end

  def test_login_shell_sources_both_logout_files
    File.write(File.join(@tempdir, '.bash_logout'), 'BASH_LOGOUT_SOURCED=yes')
    File.write(File.join(@tempdir, '.rubish_logout'), 'RUBISH_LOGOUT_SOURCED=yes')

    repl = create_test_repl(login_shell: true)
    repl.send(:load_logout_config)

    assert_equal 'yes', ENV['BASH_LOGOUT_SOURCED']
    assert_equal 'yes', ENV['RUBISH_LOGOUT_SOURCED']
  end

  def test_non_login_shell_does_not_source_logout_files
    File.write(File.join(@tempdir, '.bash_logout'), 'BASH_LOGOUT_SOURCED=yes')
    File.write(File.join(@tempdir, '.rubish_logout'), 'RUBISH_LOGOUT_SOURCED=yes')

    repl = create_test_repl(login_shell: false)
    repl.send(:load_logout_config)

    assert_nil ENV['BASH_LOGOUT_SOURCED']
    assert_nil ENV['RUBISH_LOGOUT_SOURCED']
  end

  # ==========================================================================
  # Interactive mode tests (-i flag)
  # ==========================================================================

  def test_interactive_mode_flag_is_set
    # Enable interactive mode
    Rubish::Builtins.enable_interactive_mode

    assert Rubish::Builtins.interactive_mode?
  ensure
    # Reset interactive mode
    Rubish::Builtins.instance_variable_get(:@set_options)['i'] = false
  end

  def test_interactive_mode_cannot_be_changed_via_set
    # Try to enable via set command
    repl = create_test_repl
    stderr = capture_stderr { repl.send(:execute, 'set -i') }
    assert_match(/cannot modify/, stderr)

    # Try to disable via set command
    Rubish::Builtins.enable_interactive_mode
    stderr = capture_stderr { repl.send(:execute, 'set +i') }
    assert_match(/cannot modify/, stderr)
  ensure
    Rubish::Builtins.instance_variable_get(:@set_options)['i'] = false
  end

  # ==========================================================================
  # --rcfile / --init-file tests
  # ==========================================================================

  def test_rcfile_uses_custom_file_instead_of_bashrc
    # Create custom rc file and regular bashrc
    custom_rc = File.join(@tempdir, 'custom.rc')
    File.write(custom_rc, 'CUSTOM_RC_SOURCED=yes')
    File.write(File.join(@tempdir, '.bashrc'), 'BASHRC_SOURCED=yes')
    File.write(File.join(@tempdir, '.rubishrc'), 'RUBISHRC_SOURCED=yes')

    repl = Rubish::REPL.new(rcfile: custom_rc)
    repl.send(:load_interactive_config)

    # Only custom rc should be sourced
    assert_equal 'yes', ENV['CUSTOM_RC_SOURCED']
    assert_nil ENV['BASHRC_SOURCED']
    assert_nil ENV['RUBISHRC_SOURCED']
  end

  def test_rcfile_with_tilde_expansion
    # Create custom rc file in temp home
    custom_rc = File.join(@tempdir, '.myrc')
    File.write(custom_rc, 'MYRC_SOURCED=yes')

    repl = Rubish::REPL.new(rcfile: '~/.myrc')
    repl.send(:load_interactive_config)

    assert_equal 'yes', ENV['MYRC_SOURCED']
  end

  def test_no_rc_overrides_rcfile
    # Even with rcfile specified, --norc should skip it
    custom_rc = File.join(@tempdir, 'custom.rc')
    File.write(custom_rc, 'CUSTOM_RC_SOURCED=yes')

    repl = Rubish::REPL.new(rcfile: custom_rc, no_rc: true)
    repl.send(:load_interactive_config)

    assert_nil ENV['CUSTOM_RC_SOURCED']
  end
end
