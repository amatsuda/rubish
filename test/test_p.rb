# frozen_string_literal: true

require_relative 'test_helper'

class TestP < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_p_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # ==========================================================================
  # P method tests (p prints Ruby inspect output)
  # ==========================================================================

  def test_p_simple
    # p prints each line with .inspect
    execute("printf 'hello\\nworld\\n' | p > #{output_file}")
    content = File.read(output_file)
    assert_match(/"hello"/, content)
    assert_match(/"world"/, content)
  end

  def test_p_with_special_characters
    # p shows escape sequences
    execute("printf 'tab\\there\\n' | p > #{output_file}")
    content = File.read(output_file)
    assert_match(/"tab\\there"/, content)
  end

  def test_p_function_call_single_arg
    # p("hello") should work like Ruby's p
    execute('p("hello") > ' + output_file)
    content = File.read(output_file).strip
    assert_equal '"hello"', content
  end

  def test_p_function_call_multiple_args
    # p("hello", "world") should print each arg inspected
    execute('p("hello", "world") > ' + output_file)
    content = File.read(output_file)
    assert_match(/"hello"/, content)
    assert_match(/"world"/, content)
  end

  def test_p_parsing
    tokens = Rubish::Lexer.new('seq 1 3 | p').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 'p', ast.commands.last.name
  end

  def test_p_codegen
    tokens = Rubish::Lexer.new('seq 1 3 | p').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/p __line/, code)
  end

  def test_p_func_call_codegen
    tokens = Rubish::Lexer.new('p("test")').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/p\("test"\)/, code)
  end
end
