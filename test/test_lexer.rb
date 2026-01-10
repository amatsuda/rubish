# frozen_string_literal: true

require_relative 'test_helper'

class TestLexer < Test::Unit::TestCase
  def tokenize(input)
    Rubish::Lexer.new(input).tokenize
  end

  def test_simple_command
    tokens = tokenize('ls')
    assert_equal 1, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal 'ls', tokens[0].value
  end

  def test_command_with_args
    tokens = tokenize('ls -la /tmp')
    assert_equal 3, tokens.length
    assert_equal ['ls', '-la', '/tmp'], tokens.map(&:value)
  end

  def test_pipe
    tokens = tokenize('ls | grep foo')
    assert_equal 4, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :PIPE, tokens[1].type
    assert_equal '|', tokens[1].value
    assert_equal :WORD, tokens[2].type
  end

  def test_redirect_out
    tokens = tokenize('echo hello > /tmp/file')
    assert_equal 4, tokens.length
    assert_equal :REDIRECT_OUT, tokens[2].type
    assert_equal '>', tokens[2].value
  end

  def test_redirect_append
    tokens = tokenize('echo hello >> /tmp/file')
    assert_equal 4, tokens.length
    assert_equal :REDIRECT_APPEND, tokens[2].type
    assert_equal '>>', tokens[2].value
  end

  def test_redirect_in
    tokens = tokenize('cat < /tmp/file')
    assert_equal 3, tokens.length
    assert_equal :REDIRECT_IN, tokens[1].type
  end

  def test_semicolon
    tokens = tokenize('echo a; echo b')
    assert_equal 5, tokens.length
    assert_equal :SEMICOLON, tokens[2].type
  end

  def test_ampersand
    tokens = tokenize('sleep 10 &')
    assert_equal 3, tokens.length
    assert_equal :AMPERSAND, tokens[2].type
  end

  def test_double_quoted_string
    tokens = tokenize('echo "hello world"')
    assert_equal 2, tokens.length
    assert_equal '"hello world"', tokens[1].value
  end

  def test_single_quoted_string
    tokens = tokenize("echo 'hello world'")
    assert_equal 2, tokens.length
    assert_equal "'hello world'", tokens[1].value
  end

  # New tests for parser edge cases

  # Test |& (pipe both stdout and stderr)
  def test_pipe_both
    tokens = tokenize('cmd1 |& cmd2')
    assert_equal 3, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :PIPE_BOTH, tokens[1].type
    assert_equal '|&', tokens[1].value
    assert_equal :WORD, tokens[2].type
  end

  # Test ;& (case fall-through)
  def test_case_fall
    tokens = tokenize(';&')
    assert_equal 1, tokens.length
    assert_equal :CASE_FALL, tokens[0].type
    assert_equal ';&', tokens[0].value
  end

  # Test ;;& (case continue)
  def test_case_cont
    tokens = tokenize(';;&')
    assert_equal 1, tokens.length
    assert_equal :CASE_CONT, tokens[0].type
    assert_equal ';;&', tokens[0].value
  end

  # Test ;; (double semi)
  def test_double_semi
    tokens = tokenize(';;')
    assert_equal 1, tokens.length
    assert_equal :DOUBLE_SEMI, tokens[0].type
    assert_equal ';;', tokens[0].value
  end

  # Test case with fall-through
  def test_case_with_fall_through_tokens
    tokens = tokenize('case x in a) echo a ;& b) echo b ;; esac')
    types = tokens.map(&:type)
    assert_includes types, :CASE_FALL
    assert_includes types, :DOUBLE_SEMI
  end

  # Test case with continue
  def test_case_with_continue_tokens
    tokens = tokenize('case x in a) echo a ;;& b) echo b ;; esac')
    types = tokens.map(&:type)
    assert_includes types, :CASE_CONT
    assert_includes types, :DOUBLE_SEMI
  end

  # Ensure ;;& and ;& don't conflict with each other
  def test_case_terminators_no_conflict
    tokens = tokenize(';& ;;& ;;')
    assert_equal 3, tokens.length
    assert_equal :CASE_FALL, tokens[0].type
    assert_equal :CASE_CONT, tokens[1].type
    assert_equal :DOUBLE_SEMI, tokens[2].type
  end
end
