# frozen_string_literal: true

require_relative 'test_helper'

class TestLocal < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_local_test')
    Rubish::Builtins.clear_local_scopes
    # Clean up any x variable from previous tests
    ENV.delete('x')
  end

  def teardown
    ENV.delete('x')
    Rubish::Builtins.clear_local_scopes
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test local outside function
  def test_local_outside_function
    output = capture_stderr { Rubish::Builtins.run('local', ['x=1']) }
    assert_match(/can only be used in a function/, output)
  end

  # Test scope stack operations
  def test_push_pop_scope
    Rubish::Builtins.push_local_scope
    assert Rubish::Builtins.in_function?

    Rubish::Builtins.pop_local_scope
    assert_false Rubish::Builtins.in_function?
  end

  # Test local variable with value
  def test_local_with_value
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['x=hello'])
    assert_equal 'hello', Rubish::Builtins.get_var('x')
    Rubish::Builtins.pop_local_scope
    assert_nil Rubish::Builtins.get_var('x')
  end

  # Test local preserves and restores global
  def test_local_restores_global
    ENV['x'] = 'global'
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['x=local'])
    assert_equal 'local', ENV['x']
    Rubish::Builtins.pop_local_scope
    assert_equal 'global', ENV['x']
  end

  # Test local without value
  def test_local_without_value_new_var
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['x'])
    assert_nil ENV['x']  # Not set yet
    ENV['x'] = 'value'
    assert_equal 'value', ENV['x']
    Rubish::Builtins.pop_local_scope
    assert_nil ENV['x']  # Unset after scope
  end

  def test_local_without_value_existing_var
    ENV['x'] = 'global'
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['x'])
    # Without localvar_inherit, local x unsets the variable (bash standard behavior)
    assert_nil ENV['x']
    ENV['x'] = 'modified'
    assert_equal 'modified', ENV['x']
    Rubish::Builtins.pop_local_scope
    assert_equal 'global', ENV['x']  # Restored
  end

  def test_local_without_value_with_localvar_inherit
    Rubish::Builtins.current_state.shell_options['localvar_inherit'] = true
    ENV['x'] = 'global'
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['x'])
    # With localvar_inherit, local x inherits the value
    assert_equal 'global', ENV['x']
    ENV['x'] = 'modified'
    assert_equal 'modified', ENV['x']
    Rubish::Builtins.pop_local_scope
    assert_equal 'global', ENV['x']  # Restored
  ensure
    Rubish::Builtins.current_state.shell_options.delete('localvar_inherit')
  end

  # Test multiple local variables
  def test_multiple_locals
    ENV['a'] = 'A'
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['a=1', 'b=2', 'c=3'])
    assert_equal '1', get_shell_var('a')
    assert_equal '2', get_shell_var('b')
    assert_equal '3', get_shell_var('c')
    Rubish::Builtins.pop_local_scope
    assert_equal 'A', ENV['a']
    assert_nil get_shell_var('b')
    assert_nil get_shell_var('c')
  end

  # Test nested scopes
  def test_nested_scopes
    ENV['x'] = 'global'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['x=level1'])
    assert_equal 'level1', ENV['x']

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['x=level2'])
    assert_equal 'level2', ENV['x']

    Rubish::Builtins.pop_local_scope
    assert_equal 'level1', ENV['x']

    Rubish::Builtins.pop_local_scope
    assert_equal 'global', ENV['x']
  end

  # Test local in function via REPL execution
  def test_local_in_function
    execute('myfunc() { local x=inside; echo $x; }')
    ENV['x'] = 'outside'

    execute("myfunc > #{output_file}")
    assert_equal "inside\n", File.read(output_file)
    assert_equal 'outside', ENV['x']
  end

  def test_local_modifies_only_local_scope
    execute('myfunc() { local x; export x=modified; echo $x; }')
    ENV['x'] = 'original'

    execute("myfunc > #{output_file}")
    assert_equal "modified\n", File.read(output_file)
    assert_equal 'original', ENV['x']
  end

  def test_nested_function_calls
    execute('inner() { local x=inner_val; echo inner:$x; }')
    execute('outer() { local x=outer_val; inner; echo outer:$x; }')

    execute("outer > #{output_file}")
    output = File.read(output_file)
    assert_match(/inner:inner_val/, output)
    assert_match(/outer:outer_val/, output)
  end

  # Test local -n (nameref)
  def test_local_n_creates_nameref
    ENV['target'] = 'target_value'
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['-n', 'ref=target'])
    assert Rubish::Builtins.nameref?('ref')
    assert_equal 'target', Rubish::Builtins.get_nameref_target('ref')
    Rubish::Builtins.pop_local_scope
    assert_false Rubish::Builtins.nameref?('ref')
  ensure
    ENV.delete('target')
    Rubish::Builtins.unset_nameref('ref')
  end

  def test_local_n_reads_through_ref
    ENV['target'] = 'hello'
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['-n', 'ref=target'])
    # Reading through nameref should return target's value
    assert_equal 'hello', Rubish::Builtins.get_var_through_nameref('ref')
    Rubish::Builtins.pop_local_scope
  ensure
    ENV.delete('target')
    Rubish::Builtins.unset_nameref('ref')
  end

  def test_local_n_writes_through_ref
    ENV['target'] = 'original'
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['-n', 'ref=target'])
    # Writing through nameref should modify target
    Rubish::Builtins.set_var_through_nameref('ref', 'modified')
    assert_equal 'modified', ENV['target']
    Rubish::Builtins.pop_local_scope
    # Target should still be modified (nameref was local, not the target)
    assert_equal 'modified', ENV['target']
  ensure
    ENV.delete('target')
    Rubish::Builtins.unset_nameref('ref')
  end

  def test_local_n_restores_after_scope
    ENV['target'] = 'value'
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['-n', 'ref=target'])
    assert Rubish::Builtins.nameref?('ref')
    Rubish::Builtins.pop_local_scope
    # After scope ends, ref should no longer be a nameref
    assert_false Rubish::Builtins.nameref?('ref')
  ensure
    ENV.delete('target')
  end

  def test_local_n_without_value
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['-n', 'ref'])
    # Should have nameref attribute but no target yet
    assert Rubish::Builtins.nameref?('ref')
    assert_nil Rubish::Builtins.get_nameref_target('ref')
    Rubish::Builtins.pop_local_scope
    assert_false Rubish::Builtins.nameref?('ref')
  end

  def test_local_n_nested_scopes
    ENV['target'] = 'global_target'

    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['-n', 'ref=target'])
    assert_equal 'target', Rubish::Builtins.get_nameref_target('ref')

    # Nested scope with different nameref target
    Rubish::Builtins.push_local_scope
    ENV['other'] = 'other_value'
    Rubish::Builtins.run('local', ['-n', 'ref=other'])
    assert_equal 'other', Rubish::Builtins.get_nameref_target('ref')

    Rubish::Builtins.pop_local_scope
    # Should restore to outer scope's nameref target
    assert_equal 'target', Rubish::Builtins.get_nameref_target('ref')

    Rubish::Builtins.pop_local_scope
    # Should no longer be a nameref
    assert_false Rubish::Builtins.nameref?('ref')
  ensure
    ENV.delete('target')
    ENV.delete('other')
    Rubish::Builtins.unset_nameref('ref')
  end

  def test_local_n_shadows_regular_var
    ENV['ref'] = 'regular_value'
    Rubish::Builtins.push_local_scope
    ENV['target'] = 'target_value'
    Rubish::Builtins.run('local', ['-n', 'ref=target'])
    assert Rubish::Builtins.nameref?('ref')
    Rubish::Builtins.pop_local_scope
    # Should restore to regular variable
    assert_false Rubish::Builtins.nameref?('ref')
    assert_equal 'regular_value', ENV['ref']
  ensure
    ENV.delete('ref')
    ENV.delete('target')
  end

  def test_local_n_invalid_option
    Rubish::Builtins.push_local_scope
    output = capture_stderr { Rubish::Builtins.run('local', ['-x', 'var']) }
    assert_match(/invalid option/, output)
    Rubish::Builtins.pop_local_scope
  end

  def test_local_n_multiple_namerefs
    ENV['a'] = 'val_a'
    ENV['b'] = 'val_b'
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['-n', 'ref1=a', 'ref2=b'])
    assert Rubish::Builtins.nameref?('ref1')
    assert Rubish::Builtins.nameref?('ref2')
    assert_equal 'a', Rubish::Builtins.get_nameref_target('ref1')
    assert_equal 'b', Rubish::Builtins.get_nameref_target('ref2')
    Rubish::Builtins.pop_local_scope
    assert_false Rubish::Builtins.nameref?('ref1')
    assert_false Rubish::Builtins.nameref?('ref2')
  ensure
    ENV.delete('a')
    ENV.delete('b')
    Rubish::Builtins.unset_nameref('ref1')
    Rubish::Builtins.unset_nameref('ref2')
  end

  def test_local_n_combined_with_test_R
    ENV['target'] = 'value'
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['-n', 'ref=target'])
    # test -R should return true for nameref
    assert Rubish::Builtins.run('test', ['-R', 'ref'])
    # test -R should return false for regular var
    assert_false Rubish::Builtins.run('test', ['-R', 'target'])
    Rubish::Builtins.pop_local_scope
  ensure
    ENV.delete('target')
    Rubish::Builtins.unset_nameref('ref')
  end
end
