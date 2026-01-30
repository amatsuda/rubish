# frozen_string_literal: true

require_relative 'test_helper'

class TestLocalvarUnset < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @original_env = ENV.to_h.dup
    Rubish::Builtins.clear_local_scopes
  end

  def teardown
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    Rubish::Builtins.clear_local_scopes
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # localvar_unset is disabled by default
  def test_localvar_unset_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('localvar_unset')
  end

  def test_localvar_unset_can_be_enabled
    execute('shopt -s localvar_unset')
    assert Rubish::Builtins.shopt_enabled?('localvar_unset')
  end

  def test_localvar_unset_can_be_disabled
    execute('shopt -s localvar_unset')
    execute('shopt -u localvar_unset')
    assert_false Rubish::Builtins.shopt_enabled?('localvar_unset')
  end

  # Without localvar_unset: unset removes value but scope tracking remains
  def test_unset_without_localvar_unset
    ENV['MYVAR'] = 'global'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR=local'])
    assert_equal 'local', get_shell_var('MYVAR')

    # Unset the local variable
    Rubish::Builtins.run('unset', ['MYVAR'])
    assert_nil get_shell_var('MYVAR')

    # Pop scope - original value should be restored
    Rubish::Builtins.pop_local_scope
    assert_equal 'global', get_shell_var('MYVAR')
  end

  # With localvar_unset: unset removes from scope and restores outer value immediately
  def test_unset_with_localvar_unset_restores_outer_value
    execute('shopt -s localvar_unset')
    ENV['MYVAR'] = 'global'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR=local'])
    assert_equal 'local', get_shell_var('MYVAR')

    # Unset the local variable - should immediately restore outer value
    Rubish::Builtins.run('unset', ['MYVAR'])
    assert_equal 'global', get_shell_var('MYVAR')

    # Pop scope - value remains global
    Rubish::Builtins.pop_local_scope
    assert_equal 'global', get_shell_var('MYVAR')
  end

  # With localvar_unset: unset variable that was unset in outer scope
  def test_unset_with_localvar_unset_restores_unset
    execute('shopt -s localvar_unset')
    ENV.delete('NEWVAR')

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['NEWVAR=local'])
    assert_equal 'local', get_shell_var('NEWVAR')

    # Unset - should restore to unset state
    Rubish::Builtins.run('unset', ['NEWVAR'])
    assert_nil get_shell_var('NEWVAR')

    Rubish::Builtins.pop_local_scope
    assert_nil get_shell_var('NEWVAR')
  end

  # With localvar_unset: unset non-local variable just removes it
  def test_unset_non_local_with_localvar_unset
    execute('shopt -s localvar_unset')
    ENV['GLOBALVAR'] = 'global'

    Rubish::Builtins.push_local_scope
    # Don't declare GLOBALVAR as local

    # Unset the global variable
    Rubish::Builtins.run('unset', ['GLOBALVAR'])
    assert_nil get_shell_var('GLOBALVAR')

    Rubish::Builtins.pop_local_scope
    assert_nil get_shell_var('GLOBALVAR')
  end

  # Without localvar_unset: unset and re-set keeps variable local
  def test_unset_reset_without_localvar_unset
    ENV['MYVAR'] = 'global'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR=local'])

    Rubish::Builtins.run('unset', ['MYVAR'])
    assert_nil get_shell_var('MYVAR')

    # Set it again - still in local scope
    ENV['MYVAR'] = 'new_local'
    assert_equal 'new_local', get_shell_var('MYVAR')

    Rubish::Builtins.pop_local_scope
    # Original global value restored
    assert_equal 'global', get_shell_var('MYVAR')
  end

  # With localvar_unset: unset removes from scope, so re-set goes to outer scope
  def test_unset_reset_with_localvar_unset
    execute('shopt -s localvar_unset')
    ENV['MYVAR'] = 'global'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR=local'])

    Rubish::Builtins.run('unset', ['MYVAR'])
    # Outer value restored
    assert_equal 'global', get_shell_var('MYVAR')

    # Set it again - modifies the outer scope value (not local anymore)
    set_shell_var('MYVAR', 'modified')
    assert_equal 'modified', get_shell_var('MYVAR')

    Rubish::Builtins.pop_local_scope
    # Value remains modified (was not in local scope)
    assert_equal 'modified', get_shell_var('MYVAR')
  end

  # Nested scopes with localvar_unset
  def test_nested_scopes_with_localvar_unset
    execute('shopt -s localvar_unset')
    ENV['MYVAR'] = 'global'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR=level1'])
    assert_equal 'level1', get_shell_var('MYVAR')

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR=level2'])
    assert_equal 'level2', get_shell_var('MYVAR')

    # Unset in inner scope - should restore level1 value
    Rubish::Builtins.run('unset', ['MYVAR'])
    assert_equal 'level1', get_shell_var('MYVAR')

    Rubish::Builtins.pop_local_scope
    assert_equal 'level1', get_shell_var('MYVAR')

    Rubish::Builtins.pop_local_scope
    assert_equal 'global', get_shell_var('MYVAR')
  end

  # Multiple unsets in same scope with localvar_unset
  def test_multiple_variables_unset
    execute('shopt -s localvar_unset')
    ENV['VAR1'] = 'global1'
    ENV['VAR2'] = 'global2'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['VAR1=local1', 'VAR2=local2'])

    Rubish::Builtins.run('unset', ['VAR1', 'VAR2'])
    assert_equal 'global1', get_shell_var('VAR1')
    assert_equal 'global2', get_shell_var('VAR2')

    Rubish::Builtins.pop_local_scope
    assert_equal 'global1', get_shell_var('VAR1')
    assert_equal 'global2', get_shell_var('VAR2')
  end

  # Unset outside of function with localvar_unset enabled
  def test_unset_outside_function_with_localvar_unset
    execute('shopt -s localvar_unset')
    ENV['MYVAR'] = 'value'

    # No local scope, so unset just removes the variable
    Rubish::Builtins.run('unset', ['MYVAR'])
    assert_nil get_shell_var('MYVAR')
  end

  # Unset a variable that's not in local scope with localvar_unset
  def test_unset_non_tracked_variable
    execute('shopt -s localvar_unset')
    ENV['OUTER'] = 'outer_value'
    ENV['INNER'] = 'inner_value'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['INNER=local'])

    # OUTER is not tracked in local scope
    Rubish::Builtins.run('unset', ['OUTER'])
    assert_nil get_shell_var('OUTER')

    # INNER is tracked, unset restores nothing (was not set before scope)
    Rubish::Builtins.run('unset', ['INNER'])
    assert_equal 'inner_value', get_shell_var('INNER')

    Rubish::Builtins.pop_local_scope
  end

  # Verify local scope is properly updated after unset
  def test_scope_updated_after_unset
    execute('shopt -s localvar_unset')
    ENV['MYVAR'] = 'global'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR=local'])

    # Get current scope
    scope = Rubish::Builtins.current_state.local_scope_stack.last
    assert scope.key?('MYVAR')

    Rubish::Builtins.run('unset', ['MYVAR'])

    # Variable should be removed from scope
    assert_false scope.key?('MYVAR')

    Rubish::Builtins.pop_local_scope
  end

  # Unset with -v flag (explicit variable mode)
  def test_unset_with_v_flag
    execute('shopt -s localvar_unset')
    ENV['MYVAR'] = 'global'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['MYVAR=local'])

    Rubish::Builtins.run('unset', ['-v', 'MYVAR'])
    assert_equal 'global', get_shell_var('MYVAR')

    Rubish::Builtins.pop_local_scope
  end

  # Readonly variable cannot be unset
  def test_unset_readonly_with_localvar_unset
    execute('shopt -s localvar_unset')

    Rubish::Builtins.push_local_scope
    ENV['READONLY_VAR'] = 'value'
    Rubish::Builtins.current_state.readonly_vars['READONLY_VAR'] = true

    output = capture_output do
      Rubish::Builtins.run('unset', ['READONLY_VAR'])
    end

    assert_match(/readonly variable/, output)
    assert_equal 'value', get_shell_var('READONLY_VAR')

    Rubish::Builtins.pop_local_scope
  ensure
    Rubish::Builtins.current_state.readonly_vars.delete('READONLY_VAR')
  end
end
