# frozen_string_literal: true

require_relative 'test_helper'

class TestShoptMedium < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_shopt_medium_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test that all new options exist and can be enabled/disabled

  def test_cdable_vars_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('cdable_vars')
    assert_false Rubish::Builtins.shopt_enabled?('cdable_vars')
    execute('shopt -s cdable_vars')
    assert Rubish::Builtins.shopt_enabled?('cdable_vars')
    execute('shopt -u cdable_vars')
    assert_false Rubish::Builtins.shopt_enabled?('cdable_vars')
  end

  def test_complete_fullquote_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('complete_fullquote')
    # Enabled by default
    assert Rubish::Builtins.shopt_enabled?('complete_fullquote')
    execute('shopt -u complete_fullquote')
    assert_false Rubish::Builtins.shopt_enabled?('complete_fullquote')
  end

  def test_force_fignore_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('force_fignore')
    # Enabled by default
    assert Rubish::Builtins.shopt_enabled?('force_fignore')
    execute('shopt -u force_fignore')
    assert_false Rubish::Builtins.shopt_enabled?('force_fignore')
  end

  def test_gnu_errfmt_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('gnu_errfmt')
    assert_false Rubish::Builtins.shopt_enabled?('gnu_errfmt')
    execute('shopt -s gnu_errfmt')
    assert Rubish::Builtins.shopt_enabled?('gnu_errfmt')
  end

  def test_localvar_inherit_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('localvar_inherit')
    assert_false Rubish::Builtins.shopt_enabled?('localvar_inherit')
    execute('shopt -s localvar_inherit')
    assert Rubish::Builtins.shopt_enabled?('localvar_inherit')
  end

  def test_localvar_unset_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('localvar_unset')
    assert_false Rubish::Builtins.shopt_enabled?('localvar_unset')
    execute('shopt -s localvar_unset')
    assert Rubish::Builtins.shopt_enabled?('localvar_unset')
  end

  def test_mailwarn_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('mailwarn')
    assert_false Rubish::Builtins.shopt_enabled?('mailwarn')
    execute('shopt -s mailwarn')
    assert Rubish::Builtins.shopt_enabled?('mailwarn')
  end

  def test_no_empty_cmd_completion_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('no_empty_cmd_completion')
    assert_false Rubish::Builtins.shopt_enabled?('no_empty_cmd_completion')
    execute('shopt -s no_empty_cmd_completion')
    assert Rubish::Builtins.shopt_enabled?('no_empty_cmd_completion')
  end

  def test_patsub_replacement_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('patsub_replacement')
    # Enabled by default
    assert Rubish::Builtins.shopt_enabled?('patsub_replacement')
    execute('shopt -u patsub_replacement')
    assert_false Rubish::Builtins.shopt_enabled?('patsub_replacement')
  end

  def test_progcomp_alias_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('progcomp_alias')
    assert Rubish::Builtins.shopt_enabled?('progcomp_alias')  # enabled by default
    execute('shopt -u progcomp_alias')
    assert_false Rubish::Builtins.shopt_enabled?('progcomp_alias')
  end

  # Behavioral tests for cdable_vars

  def test_cdable_vars_disabled_does_not_use_variable
    subdir = File.join(@tempdir, 'subdir')
    FileUtils.mkdir_p(subdir)
    ENV['mydir'] = subdir

    # Without cdable_vars, 'cd mydir' tries to cd to literal 'mydir' directory
    assert_false Rubish::Builtins.shopt_enabled?('cdable_vars')
    capture_stderr { execute('cd mydir') }
    # Should still be in tempdir since 'mydir' directory doesn't exist
    assert_equal File.realpath(@tempdir), File.realpath(Dir.pwd)
  end

  def test_cdable_vars_enabled_uses_variable_value
    subdir = File.join(@tempdir, 'subdir')
    FileUtils.mkdir_p(subdir)
    ENV['mydir'] = subdir

    execute('shopt -s cdable_vars')
    execute('cd mydir')
    assert_equal File.realpath(subdir), File.realpath(Dir.pwd)
  end

  def test_cdable_vars_prefers_existing_directory
    # Create an actual directory named 'mydir'
    actual_dir = File.join(@tempdir, 'mydir')
    FileUtils.mkdir_p(actual_dir)

    # Set variable to point somewhere else
    other_dir = File.join(@tempdir, 'other')
    FileUtils.mkdir_p(other_dir)
    ENV['mydir'] = other_dir

    execute('shopt -s cdable_vars')
    execute('cd mydir')
    # Should cd to actual 'mydir' directory, not the variable value
    assert_equal File.realpath(actual_dir), File.realpath(Dir.pwd)
  end

  def test_cdable_vars_with_nonexistent_variable
    execute('shopt -s cdable_vars')
    ENV.delete('nonexistent')

    capture_stderr { execute('cd nonexistent') }
    assert_equal File.realpath(@tempdir), File.realpath(Dir.pwd)
  end

  def test_cdable_vars_with_invalid_directory_in_variable
    ENV['baddir'] = '/nonexistent/path/that/does/not/exist'

    execute('shopt -s cdable_vars')
    capture_stderr { execute('cd baddir') }
    assert_equal File.realpath(@tempdir), File.realpath(Dir.pwd)
  end

  # Test that options appear in RUBISHOPTS when enabled

  def test_new_options_in_rubishopts
    execute('shopt -s cdable_vars')
    execute('shopt -s gnu_errfmt')
    execute('shopt -s mailwarn')

    result = Rubish::Builtins.rubishopts
    assert_includes result.split(':'), 'cdable_vars'
    assert_includes result.split(':'), 'gnu_errfmt'
    assert_includes result.split(':'), 'mailwarn'
  end

  # Test default-enabled options appear in RUBISHOPTS

  def test_default_enabled_options_in_rubishopts
    result = Rubish::Builtins.rubishopts
    assert_includes result.split(':'), 'complete_fullquote'
    assert_includes result.split(':'), 'force_fignore'
    assert_includes result.split(':'), 'patsub_replacement'
  end
end
