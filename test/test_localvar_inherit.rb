# frozen_string_literal: true

require_relative 'test_helper'

class TestLocalvarInherit < Test::Unit::TestCase
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

  # localvar_inherit is disabled by default
  def test_localvar_inherit_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('localvar_inherit')
  end

  def test_localvar_inherit_can_be_enabled
    execute('shopt -s localvar_inherit')
    assert Rubish::Builtins.shopt_enabled?('localvar_inherit')
  end

  def test_localvar_inherit_can_be_disabled
    execute('shopt -s localvar_inherit')
    execute('shopt -u localvar_inherit')
    assert_false Rubish::Builtins.shopt_enabled?('localvar_inherit')
  end

  # Without localvar_inherit, local var without value unsets the variable
  def test_local_without_inherit_unsets_variable
    ENV['MYVAR'] = 'outer_value'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR'])

    # Without localvar_inherit, MYVAR should be unset
    assert_nil get_shell_var('MYVAR')

    Rubish::Builtins.pop_local_scope

    # After popping scope, original value is restored
    assert_equal 'outer_value', get_shell_var('MYVAR')
  end

  # With localvar_inherit, local var without value inherits the value
  def test_local_with_inherit_keeps_value
    execute('shopt -s localvar_inherit')
    ENV['MYVAR'] = 'outer_value'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR'])

    # With localvar_inherit, MYVAR should keep its value
    assert_equal 'outer_value', get_shell_var('MYVAR')

    Rubish::Builtins.pop_local_scope

    # After popping scope, original value is still there
    assert_equal 'outer_value', get_shell_var('MYVAR')
  end

  # local var=value always sets the value regardless of localvar_inherit
  def test_local_with_value_sets_value_without_inherit
    ENV['MYVAR'] = 'outer_value'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR=local_value'])

    assert_equal 'local_value', get_shell_var('MYVAR')

    Rubish::Builtins.pop_local_scope

    assert_equal 'outer_value', get_shell_var('MYVAR')
  end

  def test_local_with_value_sets_value_with_inherit
    execute('shopt -s localvar_inherit')
    ENV['MYVAR'] = 'outer_value'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR=local_value'])

    assert_equal 'local_value', get_shell_var('MYVAR')

    Rubish::Builtins.pop_local_scope

    assert_equal 'outer_value', get_shell_var('MYVAR')
  end

  # Without localvar_inherit, local var for unset variable stays unset
  def test_local_unset_variable_without_inherit
    ENV.delete('NEWVAR')

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['NEWVAR'])

    assert_nil get_shell_var('NEWVAR')

    Rubish::Builtins.pop_local_scope

    assert_nil get_shell_var('NEWVAR')
  end

  # With localvar_inherit, local var for unset variable stays unset
  def test_local_unset_variable_with_inherit
    execute('shopt -s localvar_inherit')
    ENV.delete('NEWVAR')

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['NEWVAR'])

    # Nothing to inherit, so still unset
    assert_nil get_shell_var('NEWVAR')

    Rubish::Builtins.pop_local_scope

    assert_nil get_shell_var('NEWVAR')
  end

  # Test multiple variables in one local call
  def test_local_multiple_variables_without_inherit
    ENV['VAR1'] = 'value1'
    ENV['VAR2'] = 'value2'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['VAR1', 'VAR2'])

    # Both should be unset
    assert_nil get_shell_var('VAR1')
    assert_nil get_shell_var('VAR2')

    Rubish::Builtins.pop_local_scope

    assert_equal 'value1', get_shell_var('VAR1')
    assert_equal 'value2', get_shell_var('VAR2')
  end

  def test_local_multiple_variables_with_inherit
    execute('shopt -s localvar_inherit')
    ENV['VAR1'] = 'value1'
    ENV['VAR2'] = 'value2'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['VAR1', 'VAR2'])

    # Both should inherit values
    assert_equal 'value1', get_shell_var('VAR1')
    assert_equal 'value2', get_shell_var('VAR2')

    Rubish::Builtins.pop_local_scope

    assert_equal 'value1', get_shell_var('VAR1')
    assert_equal 'value2', get_shell_var('VAR2')
  end

  # Test mixed local declarations (some with value, some without)
  def test_local_mixed_declarations_without_inherit
    ENV['VAR1'] = 'outer1'
    ENV['VAR2'] = 'outer2'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['VAR1', 'VAR2=new_value'])

    # VAR1 should be unset (no value provided)
    assert_nil get_shell_var('VAR1')
    # VAR2 should have new value
    assert_equal 'new_value', get_shell_var('VAR2')

    Rubish::Builtins.pop_local_scope

    assert_equal 'outer1', get_shell_var('VAR1')
    assert_equal 'outer2', get_shell_var('VAR2')
  end

  def test_local_mixed_declarations_with_inherit
    execute('shopt -s localvar_inherit')
    ENV['VAR1'] = 'outer1'
    ENV['VAR2'] = 'outer2'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['VAR1', 'VAR2=new_value'])

    # VAR1 should inherit value
    assert_equal 'outer1', get_shell_var('VAR1')
    # VAR2 should have new value (explicit assignment overrides inherit)
    assert_equal 'new_value', get_shell_var('VAR2')

    Rubish::Builtins.pop_local_scope

    assert_equal 'outer1', get_shell_var('VAR1')
    assert_equal 'outer2', get_shell_var('VAR2')
  end

  # Test modifying local variable after declaration
  def test_modify_local_after_inherit
    execute('shopt -s localvar_inherit')
    ENV['MYVAR'] = 'outer_value'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR'])

    # Should inherit
    assert_equal 'outer_value', get_shell_var('MYVAR')

    # Now modify it
    ENV['MYVAR'] = 'modified_value'
    assert_equal 'modified_value', get_shell_var('MYVAR')

    Rubish::Builtins.pop_local_scope

    # Original value restored
    assert_equal 'outer_value', get_shell_var('MYVAR')
  end

  # Test nested scopes with localvar_inherit
  def test_nested_scopes_with_inherit
    execute('shopt -s localvar_inherit')
    ENV['MYVAR'] = 'global'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR'])
    assert_equal 'global', get_shell_var('MYVAR')

    ENV['MYVAR'] = 'level1'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR'])
    # Should inherit from level1
    assert_equal 'level1', get_shell_var('MYVAR')

    ENV['MYVAR'] = 'level2'

    Rubish::Builtins.pop_local_scope
    assert_equal 'level1', get_shell_var('MYVAR')

    Rubish::Builtins.pop_local_scope
    assert_equal 'global', get_shell_var('MYVAR')
  end

  # Test that toggling localvar_inherit mid-function works
  def test_toggle_inherit_mid_scope
    ENV['MYVAR'] = 'outer'

    Rubish::Builtins.push_local_scope

    # First local without inherit
    Rubish::Builtins.run('local', ['MYVAR'])
    assert_nil get_shell_var('MYVAR')

    ENV['MYVAR'] = 'set_in_scope'

    # Enable inherit
    execute('shopt -s localvar_inherit')

    # Declare another variable
    ENV['OTHER'] = 'other_outer'
    Rubish::Builtins.run('local', ['OTHER'])
    # OTHER should inherit since localvar_inherit is now on
    assert_equal 'other_outer', get_shell_var('OTHER')

    Rubish::Builtins.pop_local_scope

    assert_equal 'outer', get_shell_var('MYVAR')
  end

  # Test local outside function
  def test_local_outside_function_fails
    output = capture_stderr do
      result = Rubish::Builtins.run('local', ['MYVAR'])
      assert_false result
    end
    assert_match(/can only be used in a function/, output)
  end
end
