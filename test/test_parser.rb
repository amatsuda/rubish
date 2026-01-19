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

  # Test |& (pipe both stdout and stderr)
  def test_pipe_both
    ast = parse('cmd1 |& cmd2')
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 2, ast.commands.length
    assert_equal ['cmd1', 'cmd2'], ast.commands.map(&:name)
    assert_equal [:pipe_both], ast.pipe_types
  end

  def test_pipe_both_mixed
    ast = parse('cmd1 | cmd2 |& cmd3')
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 3, ast.commands.length
    assert_equal [:pipe, :pipe_both], ast.pipe_types
  end

  # Test ! (pipeline negation)
  def test_negation
    ast = parse('! echo hello')
    assert_instance_of Rubish::AST::Negation, ast
    assert_instance_of Rubish::AST::Command, ast.command
    assert_equal 'echo', ast.command.name
  end

  def test_negation_pipeline
    ast = parse('! cmd1 | cmd2')
    assert_instance_of Rubish::AST::Negation, ast
    assert_instance_of Rubish::AST::Pipeline, ast.command
  end

  def test_negation_with_time
    ast = parse('! time cmd')
    assert_instance_of Rubish::AST::Negation, ast
    assert_instance_of Rubish::AST::Time, ast.command
  end

  # Test case fall-through terminators
  def test_case_fall_through
    ast = parse('case x in a) echo a ;& b) echo b ;; esac')
    assert_instance_of Rubish::AST::Case, ast
    assert_equal 2, ast.branches.length
    # branches now have [patterns, body, terminator]
    assert_equal :fall, ast.branches[0][2]
    assert_equal :double_semi, ast.branches[1][2]
  end

  def test_case_continue
    ast = parse('case x in a) echo a ;;& b) echo b ;; esac')
    assert_instance_of Rubish::AST::Case, ast
    assert_equal 2, ast.branches.length
    assert_equal :cont, ast.branches[0][2]
    assert_equal :double_semi, ast.branches[1][2]
  end

  def test_case_mixed_terminators
    ast = parse('case x in a) echo a ;& b) echo b ;;& c) echo c ;; esac')
    assert_instance_of Rubish::AST::Case, ast
    assert_equal 3, ast.branches.length
    assert_equal :fall, ast.branches[0][2]
    assert_equal :cont, ast.branches[1][2]
    assert_equal :double_semi, ast.branches[2][2]
  end

  # ==========================================================================
  # Function call syntax: cmd(arg1, arg2)
  # ==========================================================================

  def test_func_call_simple
    ast = parse('ls(-l)')
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'ls', ast.name
    assert_equal ['-l'], ast.args
  end

  def test_func_call_multiple_args
    ast = parse('grep(/error/, log.txt)')
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'grep', ast.name
    assert_equal ['/error/', 'log.txt'], ast.args
  end

  # ==========================================================================
  # Method chain syntax: cmd.method(args) -> pipeline
  # ==========================================================================

  def test_method_chain_simple
    ast = parse('ls.grep(/foo/)')
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 2, ast.commands.length
    assert_equal 'ls', ast.commands[0].name
    assert_equal 'grep', ast.commands[1].name
    assert_equal ['/foo/'], ast.commands[1].args
  end

  def test_method_chain_multiple
    ast = parse('ls.grep(/foo/).head(-5)')
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 3, ast.commands.length
    assert_equal 'ls', ast.commands[0].name
    assert_equal 'grep', ast.commands[1].name
    assert_equal 'head', ast.commands[2].name
    assert_equal ['-5'], ast.commands[2].args
  end

  # ==========================================================================
  # head/tail argument transformation: bare integers -> -n form
  # ==========================================================================

  def test_head_bare_integer_transformed
    ast = parse('head(5)')
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'head', ast.name
    assert_equal ['-n', '5'], ast.args
  end

  def test_tail_bare_integer_transformed
    ast = parse('tail(10)')
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'tail', ast.name
    assert_equal ['-n', '10'], ast.args
  end

  def test_head_negative_integer_unchanged
    ast = parse('head(-5)')
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'head', ast.name
    assert_equal ['-5'], ast.args
  end

  def test_head_with_explicit_n_flag
    ast = parse('head(-n, 5)')
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'head', ast.name
    assert_equal ['-n', '5'], ast.args
  end

  def test_head_with_c_flag
    ast = parse('head(-c, 100)')
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'head', ast.name
    assert_equal ['-c', '100'], ast.args
  end

  def test_method_chain_with_head_transform
    ast = parse('ls.head(5)')
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 2, ast.commands.length
    assert_equal 'ls', ast.commands[0].name
    assert_equal 'head', ast.commands[1].name
    assert_equal ['-n', '5'], ast.commands[1].args
  end

  def test_method_chain_with_tail_transform
    ast = parse('ls.tail(1)')
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 2, ast.commands.length
    assert_equal 'ls', ast.commands[0].name
    assert_equal 'tail', ast.commands[1].name
    assert_equal ['-n', '1'], ast.commands[1].args
  end

  # ==========================================================================
  # Each method: cmd.each {|var| body } - parsed as pipeline with each command
  # ==========================================================================

  def test_each_simple
    ast = parse('ls.each {|x| echo $x }')
    # each is now a regular command in the pipeline
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 2, ast.commands.length
    assert_equal 'ls', ast.commands[0].name
    assert_equal 'each', ast.commands[1].name
    assert_match(/\|x\|/, ast.commands[1].block)
  end

  def test_each_with_pipeline_source
    ast = parse('ls.grep(/foo/).each {|line| echo $line }')
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 3, ast.commands.length
    assert_equal 'ls', ast.commands[0].name
    assert_equal 'grep', ast.commands[1].name
    assert_equal 'each', ast.commands[2].name
    assert_match(/\|line\|/, ast.commands[2].block)
  end

  def test_each_with_func_call_source
    ast = parse('seq(1, 10).each {|n| echo $n }')
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 2, ast.commands.length
    assert_equal 'seq', ast.commands[0].name
    assert_equal ['1', '10'], ast.commands[0].args
    assert_equal 'each', ast.commands[1].name
    assert_match(/\|n\|/, ast.commands[1].block)
  end
end
