# frozen_string_literal: true

require_relative 'test_helper'

class TestDeclareNameref < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_nameref_test')
    Dir.chdir(@tempdir)
    Rubish::Builtins.namerefs.clear
    Rubish::Builtins.var_attributes.clear
    Rubish::Builtins.readonly_vars.clear
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.namerefs.clear
    Rubish::Builtins.var_attributes.clear
    Rubish::Builtins.readonly_vars.clear
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Basic declare -n functionality

  def test_declare_n_creates_nameref
    execute('declare -n ref=target')
    assert Rubish::Builtins.nameref?('ref')
    assert_equal 'target', Rubish::Builtins.get_nameref_target('ref')
  end

  def test_nameref_attribute_is_set
    execute('declare -n ref=target')
    attrs = Rubish::Builtins.get_var_attributes('ref')
    assert attrs.include?(:nameref)
  end

  def test_declare_n_without_value
    execute('declare -n ref')
    assert Rubish::Builtins.nameref?('ref')
  end

  # Reading through nameref

  def test_nameref_reads_target_value
    ENV['target'] = 'hello'
    execute('declare -n ref=target')
    value = Rubish::Builtins.get_var_through_nameref('ref')
    assert_equal 'hello', value
  end

  def test_nameref_reads_empty_if_target_unset
    ENV.delete('target')
    execute('declare -n ref=target')
    value = Rubish::Builtins.get_var_through_nameref('ref')
    assert_equal '', value
  end

  # Writing through nameref

  def test_nameref_writes_to_target
    execute('declare -n ref=target')
    Rubish::Builtins.set_var_through_nameref('ref', 'world')
    assert_equal 'world', get_shell_var('target')
  end

  def test_set_var_with_attributes_follows_nameref
    ENV['target'] = 'old'
    execute('declare -n ref=target')
    Rubish::Builtins.set_var_with_attributes('ref', 'new')
    assert_equal 'new', get_shell_var('target')
  end

  # Nameref chains

  def test_nameref_chain_two_levels
    ENV['final'] = 'value'
    Rubish::Builtins.set_nameref('ref1', 'ref2')
    Rubish::Builtins.set_nameref('ref2', 'final')
    target = Rubish::Builtins.resolve_nameref('ref1')
    assert_equal 'final', target
  end

  def test_nameref_chain_three_levels
    ENV['end'] = 'result'
    Rubish::Builtins.set_nameref('a', 'b')
    Rubish::Builtins.set_nameref('b', 'c')
    Rubish::Builtins.set_nameref('c', 'end')
    target = Rubish::Builtins.resolve_nameref('a')
    assert_equal 'end', target
  end

  # Circular reference detection

  def test_circular_nameref_detected
    Rubish::Builtins.set_nameref('a', 'b')
    Rubish::Builtins.set_nameref('b', 'a')
    # Should return nil and print error
    target = Rubish::Builtins.resolve_nameref('a')
    assert_nil target
  end

  def test_self_referential_nameref_detected
    Rubish::Builtins.set_nameref('x', 'x')
    target = Rubish::Builtins.resolve_nameref('x')
    assert_nil target
  end

  # Removing nameref attribute

  def test_remove_nameref_attribute
    execute('declare -n ref=target')
    assert Rubish::Builtins.nameref?('ref')
    execute('declare +n ref')
    assert_false Rubish::Builtins.nameref?('ref')
  end

  def test_unset_nameref_removes_mapping
    execute('declare -n ref=target')
    assert_equal 'target', Rubish::Builtins.get_nameref_target('ref')
    Rubish::Builtins.unset_nameref('ref')
    assert_nil Rubish::Builtins.get_nameref_target('ref')
    assert_false Rubish::Builtins.nameref?('ref')
  end

  # Nameref with arrays

  def test_nameref_to_array
    Rubish::Builtins.set_array('arr', ['one', 'two', 'three'])
    execute('declare -n ref=arr')
    value = Rubish::Builtins.get_var_through_nameref('ref')
    assert_equal 'one two three', value
  end

  def test_nameref_write_to_array_element
    Rubish::Builtins.set_array('arr', ['a', 'b', 'c'])
    execute('declare -n ref=arr')
    Rubish::Builtins.set_var_through_nameref('ref', 'new')
    arr = Rubish::Builtins.get_array('arr')
    assert_equal 'new', arr[0]
  end

  # Nameref with associative arrays

  def test_nameref_to_assoc_array
    Rubish::Builtins.set_assoc_array('hash', {'key1' => 'val1', 'key2' => 'val2'})
    execute('declare -n ref=hash')
    value = Rubish::Builtins.get_var_through_nameref('ref')
    # Values joined with space
    assert_includes ['val1 val2', 'val2 val1'], value
  end

  # Print declaration with nameref

  def test_print_declaration_shows_nameref
    execute('declare -n myref=mytarget')
    output = capture_stdout { Rubish::Builtins.print_declaration('myref') }
    assert_match(/declare -n myref/, output)
    assert_match(/mytarget/, output)
  end

  # resolve_nameref returns name if not a nameref

  def test_resolve_nameref_returns_same_if_not_nameref
    ENV['regular'] = 'value'
    target = Rubish::Builtins.resolve_nameref('regular')
    assert_equal 'regular', target
  end

  # get_var_through_nameref works for regular vars

  def test_get_var_through_nameref_regular_var
    ENV['normal'] = 'test'
    value = Rubish::Builtins.get_var_through_nameref('normal')
    assert_equal 'test', value
  end

  # set_var_through_nameref works for regular vars

  def test_set_var_through_nameref_regular_var
    Rubish::Builtins.set_var_through_nameref('normal', 'test')
    assert_equal 'test', get_shell_var('normal')
  end

  # clear_namerefs

  def test_clear_namerefs
    execute('declare -n ref1=target1')
    execute('declare -n ref2=target2')
    assert Rubish::Builtins.nameref?('ref1')
    assert Rubish::Builtins.nameref?('ref2')
    Rubish::Builtins.clear_namerefs
    assert_false Rubish::Builtins.nameref?('ref1')
    assert_false Rubish::Builtins.nameref?('ref2')
  end

  # Combined with other attributes

  def test_declare_n_with_export
    execute('declare -nx ref=target')
    attrs = Rubish::Builtins.get_var_attributes('ref')
    assert attrs.include?(:nameref)
    assert attrs.include?(:export)
  end

  def test_declare_n_with_readonly
    execute('declare -nr ref=target')
    assert Rubish::Builtins.nameref?('ref')
    assert Rubish::Builtins.readonly?('ref')
  end
end
