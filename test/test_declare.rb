# frozen_string_literal: true

require_relative 'test_helper'

class TestDeclare < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_declare_test')
    Rubish::Builtins.clear_readonly_vars
    Rubish::Builtins.clear_var_attributes
  end

  def teardown
    Rubish::Builtins.clear_readonly_vars
    Rubish::Builtins.clear_var_attributes
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test declare without attributes
  def test_declare_simple
    Rubish::Builtins.run('declare', ['MYVAR=hello'])
    assert_equal 'hello', ENV['MYVAR']
  end

  # Test declare -i (integer)
  def test_declare_integer
    Rubish::Builtins.run('declare', ['-i', 'NUM=5+3'])
    assert_equal '8', ENV['NUM']
  end

  def test_declare_integer_with_vars
    ENV['X'] = '10'
    Rubish::Builtins.run('declare', ['-i', 'NUM=X+5'])
    assert_equal '15', ENV['NUM']
  end

  # Test declare -l (lowercase)
  def test_declare_lowercase
    Rubish::Builtins.run('declare', ['-l', 'LOWER=HELLO'])
    assert_equal 'hello', ENV['LOWER']
  end

  def test_declare_lowercase_persists
    Rubish::Builtins.run('declare', ['-l', 'LOWER'])
    Rubish::Builtins.run('declare', ['LOWER=WORLD'])
    assert_equal 'world', ENV['LOWER']
  end

  # Test declare -u (uppercase)
  def test_declare_uppercase
    Rubish::Builtins.run('declare', ['-u', 'UPPER=hello'])
    assert_equal 'HELLO', ENV['UPPER']
  end

  def test_declare_uppercase_persists
    Rubish::Builtins.run('declare', ['-u', 'UPPER'])
    Rubish::Builtins.run('declare', ['UPPER=world'])
    assert_equal 'WORLD', ENV['UPPER']
  end

  # Test declare -r (readonly)
  def test_declare_readonly
    Rubish::Builtins.run('declare', ['-r', 'CONST=value'])
    assert Rubish::Builtins.readonly?('CONST')
    assert_equal 'value', ENV['CONST']
  end

  def test_declare_readonly_blocks_change
    Rubish::Builtins.run('declare', ['-r', 'CONST=first'])
    output = capture_output do
      Rubish::Builtins.run('declare', ['CONST=second'])
    end
    assert_match(/readonly variable/, output)
    assert_equal 'first', ENV['CONST']
  end

  # Test declare -x (export)
  def test_declare_export
    Rubish::Builtins.run('declare', ['-x', 'EXPORTED=value'])
    assert Rubish::Builtins.has_attribute?('EXPORTED', :export)
    assert_equal 'value', ENV['EXPORTED']
  end

  # Test combined attributes
  def test_declare_combined_attrs
    Rubish::Builtins.run('declare', ['-lu', 'VAR=MixedCase'])
    # lowercase takes precedence
    assert_equal 'mixedcase', ENV['VAR']
  end

  def test_declare_integer_and_readonly
    Rubish::Builtins.run('declare', ['-ir', 'CONST=5+5'])
    assert_equal '10', ENV['CONST']
    assert Rubish::Builtins.readonly?('CONST')
  end

  # Test removing attributes with +
  def test_declare_remove_lowercase
    Rubish::Builtins.run('declare', ['-l', 'VAR=hello'])
    assert_equal 'hello', ENV['VAR']

    Rubish::Builtins.run('declare', ['+l', 'VAR'])
    Rubish::Builtins.run('declare', ['VAR=HELLO'])
    assert_equal 'HELLO', ENV['VAR']
  end

  def test_declare_remove_uppercase
    Rubish::Builtins.run('declare', ['-u', 'VAR=HELLO'])
    Rubish::Builtins.run('declare', ['+u', 'VAR'])
    Rubish::Builtins.run('declare', ['VAR=hello'])
    assert_equal 'hello', ENV['VAR']
  end

  # Test declare -p (print)
  def test_declare_print_specific
    Rubish::Builtins.run('declare', ['-i', 'NUM=42'])
    output = capture_output { Rubish::Builtins.run('declare', ['-p', 'NUM']) }
    assert_match(/declare -i NUM/, output)
    assert_match(/42/, output)
  end

  def test_declare_print_all
    Rubish::Builtins.run('declare', ['-l', 'LOWER=test'])
    Rubish::Builtins.run('declare', ['-u', 'UPPER=test'])
    output = capture_output { Rubish::Builtins.run('declare', ['-p']) }
    assert_match(/LOWER/, output)
    assert_match(/UPPER/, output)
  end

  # Test typeset alias
  def test_typeset_alias
    Rubish::Builtins.run('typeset', ['-i', 'NUM=10'])
    assert_equal '10', ENV['NUM']
    assert Rubish::Builtins.has_attribute?('NUM', :integer)
  end

  # Test declare via REPL
  def test_declare_via_repl
    execute('declare -u MYVAR=hello')
    assert_equal 'HELLO', ENV['MYVAR']
  end

  def test_declare_integer_via_repl
    execute('declare -i COUNT=1+2+3')
    assert_equal '6', ENV['COUNT']
  end

  # Test multiple variables
  def test_declare_multiple_vars
    Rubish::Builtins.run('declare', ['-l', 'A=ONE', 'B=TWO', 'C=THREE'])
    assert_equal 'one', ENV['A']
    assert_equal 'two', ENV['B']
    assert_equal 'three', ENV['C']
  end

  # Test declare without value
  def test_declare_without_value
    ENV['EXISTING'] = 'value'
    Rubish::Builtins.run('declare', ['-l', 'EXISTING'])
    # Value unchanged, but attribute set
    assert_equal 'value', ENV['EXISTING']
    assert Rubish::Builtins.has_attribute?('EXISTING', :lowercase)
  end

  # Test get_var_attributes helper
  def test_get_var_attributes
    Rubish::Builtins.run('declare', ['-ilu', 'VAR=test'])
    attrs = Rubish::Builtins.get_var_attributes('VAR')
    assert attrs.include?(:integer)
    assert attrs.include?(:lowercase)
    assert attrs.include?(:uppercase)
  end

  # Test clear_var_attributes helper
  def test_clear_var_attributes
    Rubish::Builtins.run('declare', ['-i', 'NUM=5'])
    assert Rubish::Builtins.has_attribute?('NUM', :integer)
    Rubish::Builtins.clear_var_attributes
    assert_false Rubish::Builtins.has_attribute?('NUM', :integer)
  end
end
