# frozen_string_literal: true

require_relative 'test_helper'

class TestParser < Test::Unit::TestCase
  def parse(input)
    tokens = Rubish::Lexer.new(input).tokenize
    Rubish::Parser.new(tokens).parse
  end

  def test_simple_command
    ast = parse('ls')
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'ls', ast.name
    assert_equal [], ast.args
  end

  def test_command_with_args
    ast = parse('ls -la /tmp')
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'ls', ast.name
    assert_equal ['-la', '/tmp'], ast.args
  end

  def test_pipeline
    ast = parse('ls | grep foo')
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 2, ast.commands.length
    assert_equal 'ls', ast.commands[0].name
    assert_equal 'grep', ast.commands[1].name
    assert_equal ['foo'], ast.commands[1].args
  end

  def test_pipeline_three_commands
    ast = parse('ls | grep foo | wc -l')
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 3, ast.commands.length
  end

  def test_redirect_out
    ast = parse('echo hello > /tmp/file')
    assert_instance_of Rubish::AST::Redirect, ast
    assert_equal '>', ast.operator
    assert_equal '/tmp/file', ast.target
    assert_instance_of Rubish::AST::Command, ast.command
    assert_equal 'echo', ast.command.name
  end

  def test_redirect_append
    ast = parse('echo hello >> /tmp/file')
    assert_instance_of Rubish::AST::Redirect, ast
    assert_equal '>>', ast.operator
  end

  def test_background
    ast = parse('sleep 10 &')
    assert_instance_of Rubish::AST::Background, ast
    assert_instance_of Rubish::AST::Command, ast.command
    assert_equal 'sleep', ast.command.name
  end

  def test_list_with_semicolon
    ast = parse('echo a; echo b')
    assert_instance_of Rubish::AST::List, ast
    assert_equal 2, ast.commands.length
    assert_equal 'echo', ast.commands[0].name
    assert_equal ['a'], ast.commands[0].args
    assert_equal 'echo', ast.commands[1].name
    assert_equal ['b'], ast.commands[1].args
  end
end
