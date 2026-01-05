# frozen_string_literal: true

require_relative 'test_helper'

class TestDeclareTraceInherit < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_declare_ti_test')
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

  # -t (trace) attribute tests

  def test_declare_t_sets_trace_attribute
    execute('declare -t myvar=hello')
    assert Rubish::Builtins.has_attribute?('myvar', :trace)
    assert_equal 'hello', ENV['myvar']
  end

  def test_declare_t_without_value
    execute('declare -t tracevar')
    assert Rubish::Builtins.has_attribute?('tracevar', :trace)
  end

  def test_declare_plus_t_removes_trace
    execute('declare -t myvar=hello')
    assert Rubish::Builtins.has_attribute?('myvar', :trace)
    execute('declare +t myvar')
    assert_false Rubish::Builtins.has_attribute?('myvar', :trace)
  end

  def test_declare_ti_trace_and_integer
    execute('declare -ti intvar=42')
    assert Rubish::Builtins.has_attribute?('intvar', :trace)
    assert Rubish::Builtins.has_attribute?('intvar', :integer)
    assert_equal '42', ENV['intvar']
  end

  def test_declare_tx_trace_and_export
    execute('declare -tx exportvar=value')
    assert Rubish::Builtins.has_attribute?('exportvar', :trace)
    assert Rubish::Builtins.has_attribute?('exportvar', :export)
  end

  def test_print_declaration_shows_trace
    execute('declare -t tracevar=value')
    output = capture_stdout { Rubish::Builtins.print_declaration('tracevar') }
    assert_match(/declare -t/, output)
  end

  # -I (inherit) option tests

  def test_declare_I_outside_function_has_no_effect
    ENV['myvar'] = 'original'
    Rubish::Builtins.var_attributes['myvar'] = Set[:lowercase]
    execute('declare -I myvar=NEW')
    # Outside function, -I has no effect, but existing attributes still apply
    # Since lowercase attribute exists, 'NEW' becomes 'new'
    assert_equal 'new', ENV['myvar']
  end

  def test_declare_I_inherits_value
    ENV['inheritvar'] = 'outer_value'

    Rubish::Builtins.push_local_scope

    # declare -I without value should inherit the existing value
    execute('declare -I inheritvar')
    assert_equal 'outer_value', ENV['inheritvar']

    Rubish::Builtins.pop_local_scope
  end

  def test_declare_I_inherits_attributes
    ENV['attrvar'] = 'value'
    Rubish::Builtins.var_attributes['attrvar'] = Set[:integer, :uppercase]

    Rubish::Builtins.push_local_scope

    execute('declare -I attrvar')
    attrs = Rubish::Builtins.get_var_attributes('attrvar')
    assert attrs.include?(:integer)
    assert attrs.include?(:uppercase)

    Rubish::Builtins.pop_local_scope
  end

  def test_declare_I_new_value_overrides_inherited
    ENV['overridevar'] = 'old'

    Rubish::Builtins.push_local_scope

    execute('declare -I overridevar=new')
    assert_equal 'new', ENV['overridevar']

    Rubish::Builtins.pop_local_scope
  end

  def test_declare_I_combines_with_new_attributes
    ENV['combinevar'] = 'value'
    Rubish::Builtins.var_attributes['combinevar'] = Set[:integer]

    Rubish::Builtins.push_local_scope

    execute('declare -Il combinevar')  # Add lowercase, inherit integer
    attrs = Rubish::Builtins.get_var_attributes('combinevar')
    assert attrs.include?(:integer)  # Inherited
    assert attrs.include?(:lowercase)  # New

    Rubish::Builtins.pop_local_scope
  end

  def test_declare_I_with_g_flag
    ENV['globalvar'] = 'outer'
    Rubish::Builtins.var_attributes['globalvar'] = Set[:export]

    Rubish::Builtins.push_local_scope

    execute('declare -gI globalvar=inner')
    # -g makes it global, -I inherits attributes
    attrs = Rubish::Builtins.get_var_attributes('globalvar')
    assert attrs.include?(:export)

    Rubish::Builtins.pop_local_scope
    assert_equal 'inner', ENV['globalvar']  # Persists after pop
  end

  def test_declare_I_no_previous_var
    ENV.delete('newvar')
    Rubish::Builtins.var_attributes.delete('newvar')

    Rubish::Builtins.push_local_scope

    execute('declare -I newvar=fresh')
    # No previous var to inherit from, just set new value
    assert_equal 'fresh', ENV['newvar']

    Rubish::Builtins.pop_local_scope
  end

  # Combined tests

  def test_declare_tI_trace_and_inherit
    ENV['bothvar'] = 'value'
    Rubish::Builtins.var_attributes['bothvar'] = Set[:export]

    Rubish::Builtins.push_local_scope

    execute('declare -tI bothvar')
    attrs = Rubish::Builtins.get_var_attributes('bothvar')
    assert attrs.include?(:trace)   # New
    assert attrs.include?(:export)  # Inherited

    Rubish::Builtins.pop_local_scope
  end
end
