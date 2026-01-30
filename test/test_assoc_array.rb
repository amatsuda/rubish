# frozen_string_literal: true

require_relative 'test_helper'

class TestAssocArray < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_assoc_test')
    @saved_env = ENV.to_h
    Rubish::Builtins.current_state.arrays.clear
    Rubish::Builtins.current_state.assoc_arrays.clear
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @saved_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.current_state.arrays.clear
    Rubish::Builtins.current_state.assoc_arrays.clear
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Declaration
  def test_declare_assoc_array
    execute('declare -A map')
    assert Rubish::Builtins.assoc_array?('map')
  end

  def test_declare_multiple_assoc
    execute('declare -A map1 map2')
    assert Rubish::Builtins.assoc_array?('map1')
    assert Rubish::Builtins.assoc_array?('map2')
  end

  # Element assignment
  def test_assoc_element_assignment
    execute('declare -A map')
    execute('map[key]=value')
    assert_equal 'value', Rubish::Builtins.get_assoc_element('map', 'key')
  end

  def test_assoc_multiple_elements
    execute('declare -A map')
    execute('map[a]=1')
    execute('map[b]=2')
    execute('map[c]=3')
    assert_equal({'a' => '1', 'b' => '2', 'c' => '3'}, Rubish::Builtins.get_assoc_array('map'))
  end

  # Inline declaration
  def test_assoc_inline_declaration
    execute('declare -A colors')
    execute('colors=([red]=ff0000 [green]=00ff00)')
    assert_equal 'ff0000', Rubish::Builtins.get_assoc_element('colors', 'red')
    assert_equal '00ff00', Rubish::Builtins.get_assoc_element('colors', 'green')
  end

  # Element access
  def test_assoc_element_access
    execute('declare -A map')
    execute('map[hello]=world')
    execute("echo ${map[hello]} > #{output_file}")
    assert_equal "world\n", File.read(output_file)
  end

  def test_assoc_missing_key
    execute('declare -A map')
    execute("echo ${map[nonexistent]} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  # All values
  def test_assoc_all_values_at
    execute('declare -A map')
    execute('map=([a]=1 [b]=2 [c]=3)')
    execute("echo ${map[@]} > #{output_file}")
    output = File.read(output_file).chomp.split
    assert_equal 3, output.length
    assert_include output, '1'
    assert_include output, '2'
    assert_include output, '3'
  end

  def test_assoc_all_values_star
    execute('declare -A map')
    execute('map=([x]=foo [y]=bar)')
    execute("echo ${map[*]} > #{output_file}")
    output = File.read(output_file).chomp.split
    assert_equal 2, output.length
  end

  # All keys
  def test_assoc_all_keys
    execute('declare -A map')
    execute('map=([name]=alice [age]=30)')
    execute("echo ${!map[@]} > #{output_file}")
    output = File.read(output_file).chomp.split
    assert_equal 2, output.length
    assert_include output, 'name'
    assert_include output, 'age'
  end

  # Length
  def test_assoc_length
    execute('declare -A map')
    execute('map=([a]=1 [b]=2 [c]=3)')
    execute("echo ${#map[@]} > #{output_file}")
    assert_equal "3\n", File.read(output_file)
  end

  def test_assoc_length_empty
    execute('declare -A map')
    execute("echo ${#map[@]} > #{output_file}")
    assert_equal "0\n", File.read(output_file)
  end

  # Overwrite
  def test_assoc_overwrite_value
    execute('declare -A map')
    execute('map[key]=old')
    execute('map[key]=new')
    assert_equal 'new', Rubish::Builtins.get_assoc_element('map', 'key')
  end

  # Keys with special characters
  def test_assoc_key_with_spaces
    execute('declare -A map')
    execute("map['hello world']=greeting")
    execute("echo ${map['hello world']} > #{output_file}")
    assert_equal "greeting\n", File.read(output_file)
  end

  # Variable expansion in key
  def test_assoc_variable_key
    execute('declare -A map')
    execute('map[foo]=bar')
    execute('KEY=foo')
    execute("echo ${map[$KEY]} > #{output_file}")
    assert_equal "bar\n", File.read(output_file)
  end

  # Builtin methods
  def test_assoc_array_predicate
    execute('declare -A map')
    assert Rubish::Builtins.assoc_array?('map')
    assert_false Rubish::Builtins.assoc_array?('nonexistent')
  end

  def test_unset_assoc_array
    execute('declare -A map')
    execute('map[key]=value')
    Rubish::Builtins.unset_assoc_array('map')
    assert_false Rubish::Builtins.assoc_array?('map')
  end

  def test_unset_assoc_element
    execute('declare -A map')
    execute('map=([a]=1 [b]=2)')
    Rubish::Builtins.unset_assoc_element('map', 'a')
    assert_equal '', Rubish::Builtins.get_assoc_element('map', 'a')
    assert_equal '2', Rubish::Builtins.get_assoc_element('map', 'b')
  end

  # Multiple associative arrays
  def test_multiple_assoc_arrays
    execute('declare -A map1 map2')
    execute('map1[x]=1')
    execute('map2[x]=2')
    assert_equal '1', Rubish::Builtins.get_assoc_element('map1', 'x')
    assert_equal '2', Rubish::Builtins.get_assoc_element('map2', 'x')
  end

  # Tests for unset "map[key]" shell syntax
  def test_unset_assoc_element_shell_syntax
    execute('declare -A map')
    execute('map=([a]=1 [b]=2 [c]=3)')
    execute('unset "map[b]"')
    assert_equal '1', Rubish::Builtins.get_assoc_element('map', 'a')
    assert_equal '', Rubish::Builtins.get_assoc_element('map', 'b')
    assert_equal '3', Rubish::Builtins.get_assoc_element('map', 'c')
  end

  def test_unset_assoc_element_shell_syntax_with_variable_key
    execute('declare -A map')
    execute('map=([foo]=1 [bar]=2)')
    execute('key=foo')
    execute('unset "map[$key]"')
    assert_equal '', Rubish::Builtins.get_assoc_element('map', 'foo')
    assert_equal '2', Rubish::Builtins.get_assoc_element('map', 'bar')
  end
end
