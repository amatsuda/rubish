# frozen_string_literal: true

require_relative 'test_helper'

class TestDeclareGlobal < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_declare_global_test')
    Dir.chdir(@tempdir)
    Rubish::Builtins.var_attributes.clear
    Rubish::Builtins.readonly_vars.clear
    Rubish::Builtins.clear_local_scopes
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.var_attributes.clear
    Rubish::Builtins.readonly_vars.clear
    Rubish::Builtins.clear_local_scopes
  end

  # Basic declare -g outside function

  def test_declare_g_outside_function_sets_var
    execute('declare -g myvar=hello')
    assert_equal 'hello', get_shell_var('myvar')
  end

  def test_declare_g_outside_function_same_as_declare
    execute('declare -g var1=value1')
    execute('declare var2=value2')
    assert_equal 'value1', get_shell_var('var1')
    assert_equal 'value2', get_shell_var('var2')
  end

  # declare without -g inside function (creates local)

  def test_declare_inside_function_creates_local
    ENV['testvar'] = 'original'

    # Simulate being inside a function
    Rubish::Builtins.push_local_scope

    execute('declare testvar=modified')
    assert_equal 'modified', get_shell_var('testvar')

    # When function exits, variable should be restored
    Rubish::Builtins.pop_local_scope
    assert_equal 'original', get_shell_var('testvar')
  end

  def test_declare_inside_function_new_var_is_local
    ENV.delete('newvar')

    Rubish::Builtins.push_local_scope

    execute('declare newvar=localvalue')
    assert_equal 'localvalue', get_shell_var('newvar')

    Rubish::Builtins.pop_local_scope
    # Variable should be unset after function exits
    assert_nil get_shell_var('newvar')
  end

  # declare -g inside function (creates global)

  def test_declare_g_inside_function_creates_global
    ENV['globalvar'] = 'original'

    Rubish::Builtins.push_local_scope

    execute('declare -g globalvar=modified')
    assert_equal 'modified', get_shell_var('globalvar')

    Rubish::Builtins.pop_local_scope
    # Variable should remain modified (global)
    assert_equal 'modified', get_shell_var('globalvar')
  end

  def test_declare_g_inside_function_new_var_is_global
    ENV.delete('brandnew')

    Rubish::Builtins.push_local_scope

    execute('declare -g brandnew=globalvalue')
    assert_equal 'globalvalue', get_shell_var('brandnew')

    Rubish::Builtins.pop_local_scope
    # Variable should still exist (global)
    assert_equal 'globalvalue', get_shell_var('brandnew')
  end

  # Combined flags with -g

  def test_declare_gi_global_integer
    Rubish::Builtins.push_local_scope

    execute('declare -gi intvar=42')
    assert_equal '42', get_shell_var('intvar')
    assert Rubish::Builtins.has_attribute?('intvar', :integer)

    Rubish::Builtins.pop_local_scope
    # Should still exist after function exits
    assert_equal '42', get_shell_var('intvar')
  end

  def test_declare_gx_global_export
    Rubish::Builtins.push_local_scope

    execute('declare -gx exportvar=exported')
    assert_equal 'exported', get_shell_var('exportvar')
    assert Rubish::Builtins.has_attribute?('exportvar', :export)

    Rubish::Builtins.pop_local_scope
    assert_equal 'exported', get_shell_var('exportvar')
  end

  def test_declare_gl_global_lowercase
    Rubish::Builtins.push_local_scope

    execute('declare -gl lowervar=HELLO')
    assert_equal 'hello', get_shell_var('lowervar')

    Rubish::Builtins.pop_local_scope
    assert_equal 'hello', get_shell_var('lowervar')
  end

  def test_declare_gu_global_uppercase
    Rubish::Builtins.push_local_scope

    execute('declare -gu uppervar=hello')
    assert_equal 'HELLO', get_shell_var('uppervar')

    Rubish::Builtins.pop_local_scope
    assert_equal 'HELLO', get_shell_var('uppervar')
  end

  # Nested function scopes

  def test_declare_g_in_nested_function
    ENV['nestedvar'] = 'outer'

    # Outer function
    Rubish::Builtins.push_local_scope

    # Inner function
    Rubish::Builtins.push_local_scope

    execute('declare -g nestedvar=innermodified')
    assert_equal 'innermodified', get_shell_var('nestedvar')

    Rubish::Builtins.pop_local_scope  # Exit inner
    assert_equal 'innermodified', get_shell_var('nestedvar')

    Rubish::Builtins.pop_local_scope  # Exit outer
    assert_equal 'innermodified', get_shell_var('nestedvar')
  end

  def test_declare_without_g_in_nested_function_is_local
    ENV['nestedlocal'] = 'original'

    Rubish::Builtins.push_local_scope

    Rubish::Builtins.push_local_scope
    execute('declare nestedlocal=innervalue')
    assert_equal 'innervalue', get_shell_var('nestedlocal')
    Rubish::Builtins.pop_local_scope

    # After inner function exits, restored to what outer function had
    # Since outer didn't modify it, it's still 'original'
    assert_equal 'original', get_shell_var('nestedlocal')

    Rubish::Builtins.pop_local_scope
    assert_equal 'original', get_shell_var('nestedlocal')
  end

  # declare -g with no value

  def test_declare_g_without_value
    ENV['preexisting'] = 'exists'

    Rubish::Builtins.push_local_scope

    execute('declare -g preexisting')
    # Should not change value, but won't be tracked as local
    assert_equal 'exists', get_shell_var('preexisting')

    Rubish::Builtins.pop_local_scope
    assert_equal 'exists', get_shell_var('preexisting')
  end

  # Multiple variables

  def test_declare_g_multiple_vars
    Rubish::Builtins.push_local_scope

    execute('declare -g var1=one var2=two var3=three')
    assert_equal 'one', get_shell_var('var1')
    assert_equal 'two', get_shell_var('var2')
    assert_equal 'three', get_shell_var('var3')

    Rubish::Builtins.pop_local_scope
    assert_equal 'one', get_shell_var('var1')
    assert_equal 'two', get_shell_var('var2')
    assert_equal 'three', get_shell_var('var3')
  end

  # in_function? helper

  def test_in_function_false_by_default
    assert_false Rubish::Builtins.in_function?
  end

  def test_in_function_true_after_push
    Rubish::Builtins.push_local_scope
    assert Rubish::Builtins.in_function?
    Rubish::Builtins.pop_local_scope
  end

  def test_in_function_false_after_pop
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.pop_local_scope
    assert_false Rubish::Builtins.in_function?
  end

  # Compare declare with local

  def test_declare_behaves_like_local_in_function
    ENV['comparevar'] = 'before'

    Rubish::Builtins.push_local_scope

    # Both should behave the same
    execute('local localvar=localval')
    execute('declare declarevar=declareval')

    assert_equal 'localval', get_shell_var('localvar')
    assert_equal 'declareval', get_shell_var('declarevar')

    Rubish::Builtins.pop_local_scope

    # Both should be unset after function exits
    assert_nil get_shell_var('localvar')
    assert_nil get_shell_var('declarevar')
  end
end
