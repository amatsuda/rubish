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
end
