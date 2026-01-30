# frozen_string_literal: true

require_relative 'test_helper'

class TestSetopt < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @original_zsh_options = Rubish::Builtins.current_state.zsh_options.dup
    @tempdir = Dir.mktmpdir('rubish_setopt_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    Rubish::Builtins.current_state.zsh_options.clear
    @original_zsh_options.each { |k, v| Rubish::Builtins.current_state.zsh_options[k] = v }
  end

  # Basic setopt functionality

  def test_setopt_enables_zsh_option
    result = Rubish::Builtins.run('setopt', ['auto_pushd'])
    assert result
    assert Rubish::Builtins.zsh_option_enabled?('auto_pushd')
  end

  def test_setopt_case_insensitive
    result = Rubish::Builtins.run('setopt', ['AUTO_PUSHD'])
    assert result
    assert Rubish::Builtins.zsh_option_enabled?('auto_pushd')
  end

  def test_setopt_ignores_underscores
    result = Rubish::Builtins.run('setopt', ['autopushd'])
    assert result
    assert Rubish::Builtins.zsh_option_enabled?('auto_pushd')
  end

  def test_setopt_with_no_prefix_disables
    Rubish::Builtins.run('setopt', ['auto_pushd'])
    assert Rubish::Builtins.zsh_option_enabled?('auto_pushd')

    result = Rubish::Builtins.run('setopt', ['noautopushd'])
    assert result
    refute Rubish::Builtins.zsh_option_enabled?('auto_pushd')
  end

  def test_setopt_bash_compatible_option
    # autocd is a bash-compatible option
    result = Rubish::Builtins.run('setopt', ['autocd'])
    assert result
    assert Rubish::Builtins.shopt_enabled?('autocd')
  end

  def test_setopt_globdots_maps_to_dotglob
    result = Rubish::Builtins.run('setopt', ['globdots'])
    assert result
    assert Rubish::Builtins.shopt_enabled?('dotglob')
  end

  def test_setopt_invalid_option
    result = Rubish::Builtins.run('setopt', ['nonexistent_option_xyz'])
    refute result
  end

  def test_setopt_multiple_options
    result = Rubish::Builtins.run('setopt', ['auto_pushd', 'pushd_silent'])
    assert result
    assert Rubish::Builtins.zsh_option_enabled?('auto_pushd')
    assert Rubish::Builtins.zsh_option_enabled?('pushd_silent')
  end

  def test_setopt_without_args_lists_enabled
    Rubish::Builtins.run('setopt', ['auto_pushd'])

    output = capture_stdout do
      Rubish::Builtins.run('setopt', [])
    end

    assert output.include?('auto_pushd')
  end

  # Basic unsetopt functionality

  def test_unsetopt_disables_zsh_option
    Rubish::Builtins.run('setopt', ['auto_pushd'])
    assert Rubish::Builtins.zsh_option_enabled?('auto_pushd')

    result = Rubish::Builtins.run('unsetopt', ['auto_pushd'])
    assert result
    refute Rubish::Builtins.zsh_option_enabled?('auto_pushd')
  end

  def test_unsetopt_case_insensitive
    Rubish::Builtins.run('setopt', ['auto_pushd'])

    result = Rubish::Builtins.run('unsetopt', ['AUTO_PUSHD'])
    assert result
    refute Rubish::Builtins.zsh_option_enabled?('auto_pushd')
  end

  def test_unsetopt_with_no_prefix_enables
    # Ensure auto_pushd is off first
    Rubish::Builtins.run('unsetopt', ['auto_pushd'])
    refute Rubish::Builtins.zsh_option_enabled?('auto_pushd')

    result = Rubish::Builtins.run('unsetopt', ['noautopushd'])
    assert result
    assert Rubish::Builtins.zsh_option_enabled?('auto_pushd')
  end

  def test_unsetopt_bash_compatible_option
    Rubish::Builtins.run('setopt', ['autocd'])
    assert Rubish::Builtins.shopt_enabled?('autocd')

    result = Rubish::Builtins.run('unsetopt', ['autocd'])
    assert result
    refute Rubish::Builtins.shopt_enabled?('autocd')
  end

  def test_unsetopt_invalid_option
    result = Rubish::Builtins.run('unsetopt', ['nonexistent_option_xyz'])
    refute result
  end

  def test_unsetopt_without_args_lists_disabled
    Rubish::Builtins.run('unsetopt', ['auto_pushd'])

    output = capture_stdout do
      Rubish::Builtins.run('unsetopt', [])
    end

    assert output.include?('auto_pushd')
  end

  # Integration tests via execute

  def test_setopt_via_execute
    execute('setopt auto_pushd')
    assert Rubish::Builtins.zsh_option_enabled?('auto_pushd')
  end

  def test_unsetopt_via_execute
    execute('setopt auto_pushd')
    execute('unsetopt auto_pushd')
    refute Rubish::Builtins.zsh_option_enabled?('auto_pushd')
  end

  # Test zsh option name normalization

  def test_normalize_zsh_option
    # All these should be equivalent
    assert_equal 'autopushd', Rubish::Builtins.normalize_zsh_option('auto_pushd')
    assert_equal 'autopushd', Rubish::Builtins.normalize_zsh_option('AUTO_PUSHD')
    assert_equal 'autopushd', Rubish::Builtins.normalize_zsh_option('AutoPushD')
    assert_equal 'autopushd', Rubish::Builtins.normalize_zsh_option('autopushd')
  end

  def test_find_zsh_option_returns_type_and_name
    result = Rubish::Builtins.find_zsh_option('auto_pushd')
    assert_equal [:zsh, 'auto_pushd'], result

    result = Rubish::Builtins.find_zsh_option('autocd')
    assert_equal [:bash, 'autocd'], result
  end

  def test_find_zsh_option_with_alias
    # globdots is an alias for dotglob in bash
    result = Rubish::Builtins.find_zsh_option('globdots')
    assert_equal [:bash, 'dotglob'], result
  end
end
