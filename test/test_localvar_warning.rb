# frozen_string_literal: true

require_relative 'test_helper'

class TestLocalvarWarning < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_env = ENV.to_h.dup
    Rubish::Builtins.clear_local_scopes
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    Rubish::Builtins.clear_local_scopes
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # localvar_warning is disabled by default
  def test_localvar_warning_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('localvar_warning')
  end

  def test_localvar_warning_can_be_enabled
    execute('shopt -s localvar_warning')
    assert Rubish::Builtins.shopt_enabled?('localvar_warning')
  end

  def test_localvar_warning_can_be_disabled
    execute('shopt -s localvar_warning')
    execute('shopt -u localvar_warning')
    assert_false Rubish::Builtins.shopt_enabled?('localvar_warning')
  end

  def test_localvar_warning_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('localvar_warning')
    assert_equal false, Rubish::Builtins::SHELL_OPTIONS['localvar_warning'][0]
  end

  def test_localvar_warning_description
    desc = Rubish::Builtins::SHELL_OPTIONS['localvar_warning'][1]
    assert_match(/shadow/i, desc, 'Description should mention shadowing')
  end

  # No warning when localvar_warning is disabled
  def test_no_warning_when_disabled
    ENV['MYVAR'] = 'outer_value'

    stderr_output = capture_stderr do
      Rubish::Builtins.push_local_scope
      Rubish::Builtins.run('local', ['MYVAR'])
      Rubish::Builtins.pop_local_scope
    end

    assert_empty stderr_output, 'No warning should be printed when localvar_warning is disabled'
  end

  # Warning when localvar_warning is enabled and variable exists
  def test_warning_when_enabled_and_shadowing
    execute('shopt -s localvar_warning')
    ENV['MYVAR'] = 'outer_value'

    stderr_output = capture_stderr do
      Rubish::Builtins.push_local_scope
      Rubish::Builtins.run('local', ['MYVAR'])
      Rubish::Builtins.pop_local_scope
    end

    assert_match(/MYVAR/, stderr_output, 'Warning should mention the variable name')
    assert_match(/shadow/i, stderr_output, 'Warning should mention shadowing')
  end

  # Warning when declaring local with value and shadowing
  def test_warning_when_shadowing_with_value
    execute('shopt -s localvar_warning')
    ENV['MYVAR'] = 'outer_value'

    stderr_output = capture_stderr do
      Rubish::Builtins.push_local_scope
      Rubish::Builtins.run('local', ['MYVAR=local_value'])
      Rubish::Builtins.pop_local_scope
    end

    assert_match(/MYVAR/, stderr_output, 'Warning should mention the variable name')
  end

  # No warning when variable doesn't exist in outer scope
  def test_no_warning_when_not_shadowing
    execute('shopt -s localvar_warning')
    ENV.delete('NEWVAR')

    stderr_output = capture_stderr do
      Rubish::Builtins.push_local_scope
      Rubish::Builtins.run('local', ['NEWVAR=value'])
      Rubish::Builtins.pop_local_scope
    end

    assert_empty stderr_output, 'No warning should be printed when not shadowing'
  end

  # No warning when redeclaring in same scope
  def test_no_warning_when_redeclaring_in_same_scope
    execute('shopt -s localvar_warning')
    ENV['MYVAR'] = 'outer_value'

    stderr_output = capture_stderr do
      Rubish::Builtins.push_local_scope
      Rubish::Builtins.run('local', ['MYVAR=first'])
      # Second declaration in same scope should not warn
      Rubish::Builtins.run('local', ['MYVAR=second'])
      Rubish::Builtins.pop_local_scope
    end

    # Should only have one warning (from first declaration)
    assert_equal 1, stderr_output.scan(/shadow/i).count, 'Should only warn once per scope'
  end

  # Warning for multiple variables
  def test_warning_for_multiple_variables
    execute('shopt -s localvar_warning')
    ENV['VAR1'] = 'value1'
    ENV['VAR2'] = 'value2'
    ENV.delete('VAR3')

    stderr_output = capture_stderr do
      Rubish::Builtins.push_local_scope
      Rubish::Builtins.run('local', ['VAR1', 'VAR2', 'VAR3'])
      Rubish::Builtins.pop_local_scope
    end

    assert_match(/VAR1/, stderr_output, 'Should warn about VAR1')
    assert_match(/VAR2/, stderr_output, 'Should warn about VAR2')
    refute_match(/VAR3/, stderr_output, 'Should not warn about VAR3 (not shadowing)')
  end

  # Shopt query mode
  def test_shopt_q_localvar_warning
    result = Rubish::Builtins.run('shopt', ['-q', 'localvar_warning'])
    assert_false result

    Rubish::Builtins.run('shopt', ['-s', 'localvar_warning'])
    result = Rubish::Builtins.run('shopt', ['-q', 'localvar_warning'])
    assert result
  end

  # warn_shadow method exists
  def test_warn_shadow_method_exists
    assert Rubish::Builtins.respond_to?(:warn_shadow)
  end
end
