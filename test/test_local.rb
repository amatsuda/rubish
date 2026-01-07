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
    output = capture_output { Rubish::Builtins.run('local', ['x=1']) }
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
    assert_equal 'hello', ENV['x']
    Rubish::Builtins.pop_local_scope
    assert_nil ENV['x']
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
    Rubish::Builtins.shell_options['localvar_inherit'] = true
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
    Rubish::Builtins.shell_options.delete('localvar_inherit')
  end

  # Test multiple local variables
  def test_multiple_locals
    ENV['a'] = 'A'
    Rubish::Builtins.push_local_scope
    Rubish::Builtins.run('local', ['a=1', 'b=2', 'c=3'])
    assert_equal '1', ENV['a']
    assert_equal '2', ENV['b']
    assert_equal '3', ENV['c']
    Rubish::Builtins.pop_local_scope
    assert_equal 'A', ENV['a']
    assert_nil ENV['b']
    assert_nil ENV['c']
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
end
