# frozen_string_literal: true

require_relative 'test_helper'

# `cmd & other` must background cmd, not treat & as a plain separator
class TestBackgroundInList < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('wait') rescue nil
  end

  def parse(input)
    tokens = Rubish::Lexer.new(input).tokenize
    Rubish::Parser.new(tokens).parse
  end

  def test_ampersand_followed_by_command_parses_as_background
    ast = parse('sleep 10 & echo done')
    assert_instance_of Rubish::AST::List, ast
    assert_instance_of Rubish::AST::Background, ast.commands[0]
    assert_equal 'sleep', ast.commands[0].command.name
    assert_equal 'echo', ast.commands[1].name
  end

  def test_ampersand_followed_by_assignment_parses_as_background
    ast = parse('sleep 10 & x=1')
    assert_instance_of Rubish::AST::Background, ast.commands[0]
  end

  def test_background_then_command_does_not_block
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    execute('sleep 2 & echo after')
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert elapsed < 1.5, "expected sleep to run in background, took #{elapsed.round(2)}s"
  end

  def test_background_then_command_sets_last_background_pid
    execute('sleep 0.2 & RUBISH_BG_PID_TEST=$!')
    pid = get_shell_var('RUBISH_BG_PID_TEST')
    assert_match(/\A\d+\z/, pid.to_s)
  end
end
