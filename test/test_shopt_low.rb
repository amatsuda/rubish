# frozen_string_literal: true

require_relative 'test_helper'

class TestShoptLow < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_env = ENV.to_h.dup
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test that all new options exist and can be enabled/disabled

  def test_assoc_expand_once_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('assoc_expand_once')
    assert_false Rubish::Builtins.shopt_enabled?('assoc_expand_once')
    execute('shopt -s assoc_expand_once')
    assert Rubish::Builtins.shopt_enabled?('assoc_expand_once')
    execute('shopt -u assoc_expand_once')
    assert_false Rubish::Builtins.shopt_enabled?('assoc_expand_once')
  end

  def test_compat31_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat31')
    assert_false Rubish::Builtins.shopt_enabled?('compat31')
    execute('shopt -s compat31')
    assert Rubish::Builtins.shopt_enabled?('compat31')
  end

  def test_compat32_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat32')
    assert_false Rubish::Builtins.shopt_enabled?('compat32')
    execute('shopt -s compat32')
    assert Rubish::Builtins.shopt_enabled?('compat32')
  end

  def test_compat40_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat40')
    assert_false Rubish::Builtins.shopt_enabled?('compat40')
    execute('shopt -s compat40')
    assert Rubish::Builtins.shopt_enabled?('compat40')
  end

  def test_compat41_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat41')
    assert_false Rubish::Builtins.shopt_enabled?('compat41')
    execute('shopt -s compat41')
    assert Rubish::Builtins.shopt_enabled?('compat41')
  end

  def test_compat42_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat42')
    assert_false Rubish::Builtins.shopt_enabled?('compat42')
    execute('shopt -s compat42')
    assert Rubish::Builtins.shopt_enabled?('compat42')
  end

  def test_compat43_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat43')
    assert_false Rubish::Builtins.shopt_enabled?('compat43')
    execute('shopt -s compat43')
    assert Rubish::Builtins.shopt_enabled?('compat43')
  end

  def test_compat44_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat44')
    assert_false Rubish::Builtins.shopt_enabled?('compat44')
    execute('shopt -s compat44')
    assert Rubish::Builtins.shopt_enabled?('compat44')
  end

  def test_extdebug_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('extdebug')
    assert_false Rubish::Builtins.shopt_enabled?('extdebug')
    execute('shopt -s extdebug')
    assert Rubish::Builtins.shopt_enabled?('extdebug')
    execute('shopt -u extdebug')
    assert_false Rubish::Builtins.shopt_enabled?('extdebug')
  end

  def test_noexpand_translation_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('noexpand_translation')
    assert_false Rubish::Builtins.shopt_enabled?('noexpand_translation')
    execute('shopt -s noexpand_translation')
    assert Rubish::Builtins.shopt_enabled?('noexpand_translation')
    execute('shopt -u noexpand_translation')
    assert_false Rubish::Builtins.shopt_enabled?('noexpand_translation')
  end

  def test_restricted_shell_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('restricted_shell')
    assert_false Rubish::Builtins.shopt_enabled?('restricted_shell')
  end

  def test_restricted_shell_is_readonly
    # restricted_shell is read-only
    output = capture_stdout { execute('shopt -s restricted_shell') }
    assert_match(/cannot set option/, output)
    assert_false Rubish::Builtins.shopt_enabled?('restricted_shell')
  end

  def test_varredir_close_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('varredir_close')
    assert_false Rubish::Builtins.shopt_enabled?('varredir_close')
    execute('shopt -s varredir_close')
    assert Rubish::Builtins.shopt_enabled?('varredir_close')
    execute('shopt -u varredir_close')
    assert_false Rubish::Builtins.shopt_enabled?('varredir_close')
  end

  # Test compat options are in COMPAT_OPTIONS

  def test_compat_options_list
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat10'
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat31'
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat32'
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat40'
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat41'
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat42'
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat43'
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat44'
  end

  # Test mutual exclusivity of compat options

  def test_compat_options_mutual_exclusivity
    execute('shopt -s compat31')
    assert Rubish::Builtins.shopt_enabled?('compat31')

    # Enabling another compat option should disable compat31
    execute('shopt -s compat42')
    assert Rubish::Builtins.shopt_enabled?('compat42')
    assert_false Rubish::Builtins.shopt_enabled?('compat31')
  end

  # Test that options appear in RUBISHOPTS when enabled

  def test_new_options_in_rubishopts
    execute('shopt -s assoc_expand_once')
    execute('shopt -s extdebug')
    execute('shopt -s varredir_close')

    result = Rubish::Builtins.rubishopts
    assert_includes result.split(':'), 'assoc_expand_once'
    assert_includes result.split(':'), 'extdebug'
    assert_includes result.split(':'), 'varredir_close'
  end

  def test_compat_option_in_rubishopts
    execute('shopt -s compat43')

    result = Rubish::Builtins.rubishopts
    assert_includes result.split(':'), 'compat43'
  end
end
