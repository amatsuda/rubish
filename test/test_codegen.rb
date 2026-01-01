# frozen_string_literal: true

require_relative 'test_helper'

class TestCodegen < Test::Unit::TestCase
  def generate(input)
    tokens = Rubish::Lexer.new(input).tokenize
    ast = Rubish::Parser.new(tokens).parse
    Rubish::Codegen.new.generate(ast)
  end

  def test_simple_command
    code = generate('ls')
    assert_equal '__cmd("ls")', code
  end

  def test_command_with_args
    code = generate('ls -la /tmp')
    assert_equal '__cmd("ls", "-la", "/tmp")', code
  end

  def test_pipeline
    code = generate('ls | grep foo')
    assert_equal '__cmd("ls") | __cmd("grep", "foo")', code
  end

  def test_pipeline_three_commands
    code = generate('ls | grep foo | wc -l')
    assert_equal '__cmd("ls") | __cmd("grep", "foo") | __cmd("wc", "-l")', code
  end

  def test_redirect_out
    code = generate('echo hello > /tmp/file')
    assert_equal '__cmd("echo", "hello").redirect_out("/tmp/file")', code
  end

  def test_redirect_append
    code = generate('echo hello >> /tmp/file')
    assert_equal '__cmd("echo", "hello").redirect_append("/tmp/file")', code
  end

  def test_redirect_in
    code = generate('cat < /tmp/file')
    assert_equal '__cmd("cat").redirect_in("/tmp/file")', code
  end

  def test_background
    code = generate('sleep 10 &')
    assert_equal '__background { __cmd("sleep", "10") }', code
  end

  def test_list
    code = generate('echo a; echo b')
    assert_equal '__cmd("echo", "a"); __cmd("echo", "b")', code
  end
end
