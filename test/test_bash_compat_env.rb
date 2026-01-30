# frozen_string_literal: true

require_relative 'test_helper'

class TestBASH_COMPAT_ENV < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('bash_compat_env_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    # Clear any existing compat settings
    Rubish::Builtins.clear_compat_level
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # BASH_COMPAT env as fallback for RUBISH_COMPAT env

  def test_bash_compat_env_used_when_rubish_compat_not_set
    ENV.delete('RUBISH_COMPAT')
    ENV['BASH_COMPAT'] = '5.1'
    level = Rubish::Builtins.compat_level
    assert_equal 51, level, 'BASH_COMPAT env should be used when RUBISH_COMPAT is not set'
  end

  def test_bash_compat_env_decimal_format
    ENV.delete('RUBISH_COMPAT')
    ENV['BASH_COMPAT'] = '4.2'
    level = Rubish::Builtins.compat_level
    assert_equal 42, level
  end

  def test_bash_compat_env_integer_format
    ENV.delete('RUBISH_COMPAT')
    ENV['BASH_COMPAT'] = '50'
    level = Rubish::Builtins.compat_level
    assert_equal 500, level  # "50" is parsed as major version 50, minor 0
  end

  def test_rubish_compat_env_takes_precedence
    ENV['RUBISH_COMPAT'] = '4.3'
    ENV['BASH_COMPAT'] = '5.2'
    level = Rubish::Builtins.compat_level
    assert_equal 43, level, 'RUBISH_COMPAT env should take precedence over BASH_COMPAT'
  end

  def test_neither_env_set
    ENV.delete('RUBISH_COMPAT')
    ENV.delete('BASH_COMPAT')
    Rubish::Builtins.clear_compat_level
    level = Rubish::Builtins.compat_level
    assert_nil level, 'compat_level should be nil when neither env var is set'
  end

  def test_bash_compat_env_empty_string
    ENV.delete('RUBISH_COMPAT')
    ENV['BASH_COMPAT'] = ''
    Rubish::Builtins.clear_compat_level
    level = Rubish::Builtins.compat_level
    assert_nil level, 'Empty BASH_COMPAT should not set compat level'
  end

  def test_rubish_compat_env_empty_falls_back_to_bash
    ENV['RUBISH_COMPAT'] = ''
    ENV['BASH_COMPAT'] = '5.0'
    level = Rubish::Builtins.compat_level
    assert_equal 50, level, 'Empty RUBISH_COMPAT should fall back to BASH_COMPAT'
  end

  # compat_level? function with env vars

  def test_compat_level_check_with_bash_env
    ENV.delete('RUBISH_COMPAT')
    ENV['BASH_COMPAT'] = '4.4'
    assert Rubish::Builtins.compat_level?(44)
    assert Rubish::Builtins.compat_level?(50)
    refute Rubish::Builtins.compat_level?(43)
  end

  # Multiple version formats

  def test_bash_compat_env_version_31
    ENV.delete('RUBISH_COMPAT')
    ENV['BASH_COMPAT'] = '3.1'
    level = Rubish::Builtins.compat_level
    assert_equal 31, level
  end

  def test_bash_compat_env_version_32
    ENV.delete('RUBISH_COMPAT')
    ENV['BASH_COMPAT'] = '3.2'
    level = Rubish::Builtins.compat_level
    assert_equal 32, level
  end

  def test_bash_compat_env_version_53
    ENV.delete('RUBISH_COMPAT')
    ENV['BASH_COMPAT'] = '5.3'
    level = Rubish::Builtins.compat_level
    assert_equal 53, level
  end

  # Rubish-specific compat10

  def test_bash_compat_env_rubish_version_10
    ENV.delete('RUBISH_COMPAT')
    ENV['BASH_COMPAT'] = '1.0'
    level = Rubish::Builtins.compat_level
    assert_equal 10, level
  end
end
