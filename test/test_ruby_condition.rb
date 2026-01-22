# frozen_string_literal: true

require_relative 'test_helper'

class TestRubyCondition < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_ruby_condition_test')
    @original_env = ENV.to_h
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    # Restore original environment
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Parser tests
  def test_parse_ruby_condition
    tokens = Rubish::Lexer.new('if { true }; then echo yes; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::If, ast
    assert_instance_of Rubish::AST::RubyCondition, ast.branches.first[0]
  end

  def test_parse_ruby_condition_with_expression
    tokens = Rubish::Lexer.new('if { 1 + 1 == 2 }; then echo yes; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::RubyCondition, ast.branches.first[0]
    assert_match(/1.*\+.*1.*==.*2/, ast.branches.first[0].expression)
  end

  # Execution tests - basic conditions
  def test_ruby_condition_true
    execute("if { true }; then echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_ruby_condition_false
    File.write(output_file, 'original')
    execute("if { false }; then echo yes > #{output_file}; end")
    assert_equal 'original', File.read(output_file)
  end

  def test_ruby_condition_with_else
    execute("if { false }; then echo yes > #{output_file}; else echo no > #{output_file}; end")
    assert_equal "no\n", File.read(output_file)
  end

  # Execution tests - shell variable binding
  def test_shell_variable_binding
    ENV['VAR'] = 'foo'
    execute("if { var == 'foo' }; then echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_shell_variable_binding_false
    ENV['VAR'] = 'bar'
    execute("if { var == 'foo' }; then echo yes > #{output_file}; else echo no > #{output_file}; end")
    assert_equal "no\n", File.read(output_file)
  end

  def test_shell_variable_case_insensitive_binding
    ENV['MY_VAR'] = 'hello'
    execute("if { my_var == 'hello' }; then echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_numeric_comparison
    ENV['COUNT'] = '5'
    execute("if { count.to_i > 3 }; then echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_string_methods
    ENV['NAME'] = 'hello world'
    execute("if { name.include?('world') }; then echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_regex_match
    ENV['PATH_VAR'] = '/usr/local/bin'
    execute("if { path_var =~ /local/ }; then echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  # Execution tests - elsif with Ruby condition
  def test_elsif_ruby_condition
    ENV['VAR'] = 'bar'
    execute("if { var == 'foo' }; then echo first > #{output_file}; elsif { var == 'bar' }; then echo second > #{output_file}; end")
    assert_equal "second\n", File.read(output_file)
  end

  # Execution tests - complex expressions
  def test_complex_expression
    ENV['A'] = '10'
    ENV['B'] = '20'
    execute("if { a.to_i + b.to_i == 30 }; then echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_array_operations
    ENV['LIST'] = 'a,b,c'
    execute("if { list.split(',').length == 3 }; then echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  # Test with shell variables (not ENV)
  def test_shell_var_not_in_env
    execute('MYVAR=hello')
    execute("if { myvar == 'hello' }; then echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_shell_var_overrides_env
    ENV['TESTVAR'] = 'from_env'
    execute('TESTVAR=from_shell')
    execute("if { testvar == 'from_shell' }; then echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  # Test with function-local variables
  def test_function_local_var
    execute("myfunc() { local LOCALVAR=localvalue; if { localvar == 'localvalue' }; then echo yes > #{output_file}; end; }")
    execute('myfunc')
    assert_equal "yes\n", File.read(output_file)
  end

  def test_function_local_var_shadows_global
    execute('GLOBALVAR=global')
    execute("myfunc() { local GLOBALVAR=local; if { globalvar == 'local' }; then echo yes > #{output_file}; end; }")
    execute('myfunc')
    assert_equal "yes\n", File.read(output_file)
  end
end
