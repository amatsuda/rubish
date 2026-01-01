# frozen_string_literal: true

require_relative 'test_helper'

class TestConditional < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempfile = Tempfile.new('rubish_test')
    @tempfile.close
  end

  def teardown
    @tempfile.unlink
  end

  # Lexer tests
  def test_lexer_and
    lexer = Rubish::Lexer.new('cmd1 && cmd2')
    tokens = lexer.tokenize
    assert_equal [:WORD, :AND, :WORD], tokens.map(&:type)
  end

  def test_lexer_or
    lexer = Rubish::Lexer.new('cmd1 || cmd2')
    tokens = lexer.tokenize
    assert_equal [:WORD, :OR, :WORD], tokens.map(&:type)
  end

  def test_lexer_and_with_args
    lexer = Rubish::Lexer.new('ls -la && echo done')
    tokens = lexer.tokenize
    assert_equal [:WORD, :WORD, :AND, :WORD, :WORD], tokens.map(&:type)
  end

  # Parser tests
  def test_parser_and
    tokens = Rubish::Lexer.new('cmd1 && cmd2').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::And, ast
    assert_equal 'cmd1', ast.left.name
    assert_equal 'cmd2', ast.right.name
  end

  def test_parser_or
    tokens = Rubish::Lexer.new('cmd1 || cmd2').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Or, ast
    assert_equal 'cmd1', ast.left.name
    assert_equal 'cmd2', ast.right.name
  end

  def test_parser_chained_and
    tokens = Rubish::Lexer.new('cmd1 && cmd2 && cmd3').tokenize
    ast = Rubish::Parser.new(tokens).parse
    # Should be left-associative: (cmd1 && cmd2) && cmd3
    assert_instance_of Rubish::AST::And, ast
    assert_instance_of Rubish::AST::And, ast.left
    assert_equal 'cmd1', ast.left.left.name
    assert_equal 'cmd2', ast.left.right.name
    assert_equal 'cmd3', ast.right.name
  end

  def test_parser_mixed_and_or
    tokens = Rubish::Lexer.new('cmd1 && cmd2 || cmd3').tokenize
    ast = Rubish::Parser.new(tokens).parse
    # Should be left-associative: (cmd1 && cmd2) || cmd3
    assert_instance_of Rubish::AST::Or, ast
    assert_instance_of Rubish::AST::And, ast.left
  end

  def test_parser_pipeline_in_conditional
    tokens = Rubish::Lexer.new('cmd1 | cmd2 && cmd3').tokenize
    ast = Rubish::Parser.new(tokens).parse
    # Pipeline has higher precedence: (cmd1 | cmd2) && cmd3
    assert_instance_of Rubish::AST::And, ast
    assert_instance_of Rubish::AST::Pipeline, ast.left
  end

  # Codegen tests
  def test_codegen_and
    tokens = Rubish::Lexer.new('cmd1 && cmd2').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__and_cmd/, code)
  end

  def test_codegen_or
    tokens = Rubish::Lexer.new('cmd1 || cmd2').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__or_cmd/, code)
  end

  # Execution tests
  def test_and_success_runs_second
    execute("true && echo success > #{@tempfile.path}")
    assert_equal "success\n", File.read(@tempfile.path)
  end

  def test_and_failure_skips_second
    execute("false && echo should_not_appear > #{@tempfile.path}")
    assert_equal '', File.read(@tempfile.path)
  end

  def test_or_success_skips_second
    execute("true || echo should_not_appear > #{@tempfile.path}")
    assert_equal '', File.read(@tempfile.path)
  end

  def test_or_failure_runs_second
    execute("false || echo fallback > #{@tempfile.path}")
    assert_equal "fallback\n", File.read(@tempfile.path)
  end

  def test_chained_and_all_success
    execute("true && true && echo all_passed > #{@tempfile.path}")
    assert_equal "all_passed\n", File.read(@tempfile.path)
  end

  def test_chained_and_first_fails
    execute("false && true && echo should_not_appear > #{@tempfile.path}")
    assert_equal '', File.read(@tempfile.path)
  end

  def test_chained_and_middle_fails
    execute("true && false && echo should_not_appear > #{@tempfile.path}")
    assert_equal '', File.read(@tempfile.path)
  end

  def test_and_then_or_fallback
    execute("false && echo nope || echo fallback > #{@tempfile.path}")
    assert_equal "fallback\n", File.read(@tempfile.path)
  end

  def test_command_success_method
    cmd = Rubish::Command.new('true')
    cmd.run
    assert cmd.success?
  end

  def test_command_failure_method
    cmd = Rubish::Command.new('false')
    cmd.run
    assert !cmd.success?
  end
end
