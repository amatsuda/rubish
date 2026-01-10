# frozen_string_literal: true

require_relative 'test_helper'

class TestReadonly < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_readonly_test')
    Rubish::Builtins.clear_readonly_vars
  end

  def teardown
    Rubish::Builtins.clear_readonly_vars
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test readonly with value
  def test_readonly_with_value
    Rubish::Builtins.run('readonly', ['MYCONST=hello'])
    assert_equal 'hello', ENV['MYCONST']
    assert Rubish::Builtins.readonly?('MYCONST')
  end

  # Test readonly existing variable
  def test_readonly_existing_var
    ENV['EXISTVAR'] = 'value'
    Rubish::Builtins.run('readonly', ['EXISTVAR'])
    assert Rubish::Builtins.readonly?('EXISTVAR')
    assert_equal 'value', ENV['EXISTVAR']
  end

  # Test readonly multiple variables
  def test_readonly_multiple
    Rubish::Builtins.run('readonly', ['A=1', 'B=2', 'C=3'])
    assert_equal '1', ENV['A']
    assert_equal '2', ENV['B']
    assert_equal '3', ENV['C']
    assert Rubish::Builtins.readonly?('A')
    assert Rubish::Builtins.readonly?('B')
    assert Rubish::Builtins.readonly?('C')
  end

  # Test cannot modify readonly variable with export
  def test_export_readonly_fails
    Rubish::Builtins.run('readonly', ['MYCONST=original'])
    output = capture_output do
      Rubish::Builtins.run('export', ['MYCONST=modified'])
    end
    assert_match(/readonly variable/, output)
    assert_equal 'original', ENV['MYCONST']
  end

  # Test cannot unset readonly variable
  def test_unset_readonly_fails
    Rubish::Builtins.run('readonly', ['MYCONST=value'])
    output = capture_output do
      Rubish::Builtins.run('unset', ['MYCONST'])
    end
    assert_match(/readonly variable/, output)
    assert_equal 'value', ENV['MYCONST']
  end

  # Test cannot modify readonly with local
  def test_local_readonly_fails
    Rubish::Builtins.run('readonly', ['MYCONST=original'])
    Rubish::Builtins.push_local_scope
    output = capture_stderr do
      Rubish::Builtins.run('local', ['MYCONST=modified'])
    end
    assert_match(/readonly variable/, output)
    assert_equal 'original', ENV['MYCONST']
    Rubish::Builtins.pop_local_scope
  end

  # Test listing readonly variables
  def test_readonly_list
    Rubish::Builtins.run('readonly', ['VAR1=one'])
    Rubish::Builtins.run('readonly', ['VAR2=two'])
    output = capture_output { Rubish::Builtins.run('readonly', []) }
    assert_match(/readonly VAR1/, output)
    assert_match(/readonly VAR2/, output)
  end

  # Test readonly -p flag
  def test_readonly_p_flag
    Rubish::Builtins.run('readonly', ['MYVAR=test'])
    output = capture_output { Rubish::Builtins.run('readonly', ['-p']) }
    assert_match(/readonly MYVAR/, output)
  end

  # Test readonly via REPL
  def test_readonly_via_repl
    execute('readonly SHELLCONST=constvalue')
    assert_equal 'constvalue', ENV['SHELLCONST']
    assert Rubish::Builtins.readonly?('SHELLCONST')
  end

  # Test cannot reassign readonly via readonly command
  def test_readonly_reassign_fails
    Rubish::Builtins.run('readonly', ['MYCONST=first'])
    output = capture_output do
      Rubish::Builtins.run('readonly', ['MYCONST=second'])
    end
    assert_match(/readonly variable/, output)
    assert_equal 'first', ENV['MYCONST']
  end

  # Test readonly without value for unset variable
  def test_readonly_unset_var
    Rubish::Builtins.run('readonly', ['UNSETVAR'])
    assert Rubish::Builtins.readonly?('UNSETVAR')
    assert_nil ENV['UNSETVAR']
  end

  # Test clear_readonly_vars helper
  def test_clear_readonly_vars
    Rubish::Builtins.run('readonly', ['TESTVAR=value'])
    assert Rubish::Builtins.readonly?('TESTVAR')
    Rubish::Builtins.clear_readonly_vars
    assert_false Rubish::Builtins.readonly?('TESTVAR')
  end

  # Test readonly in function context via REPL
  def test_readonly_in_function
    execute('myfunc() { readonly LOCAL_CONST=funcval; echo $LOCAL_CONST; }')
    execute("myfunc > #{output_file}")
    assert_equal "funcval\n", File.read(output_file)
    assert Rubish::Builtins.readonly?('LOCAL_CONST')
  end
end
