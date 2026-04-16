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
    assert_equal '__cmd("ls", *["-la", "/tmp"].flatten)', code
  end

  def test_pipeline
    code = generate('ls | grep foo')
    assert_equal '__cmd("ls") | __cmd("grep", *["foo"].flatten)', code
  end

  def test_pipeline_three_commands
    code = generate('ls | grep foo | wc -l')
    assert_equal '__cmd("ls") | __cmd("grep", *["foo"].flatten) | __cmd("wc", *["-l"].flatten)', code
  end

  def test_redirect_out
    code = generate('echo hello > /tmp/file')
    assert_equal '__cmd("echo", *["hello"].flatten).redirect_out("/tmp/file")', code
  end

  def test_redirect_append
    code = generate('echo hello >> /tmp/file')
    assert_equal '__cmd("echo", *["hello"].flatten).redirect_append("/tmp/file")', code
  end

  def test_redirect_in
    code = generate('cat < /tmp/file')
    assert_equal '__cmd("cat").redirect_in("/tmp/file")', code
  end

  def test_background
    code = generate('sleep 10 &')
    assert_equal '__background { __cmd("sleep", *["10"].flatten) }', code
  end

  def test_list
    code = generate('echo a; echo b')
    assert_equal '__run_cmd { __cmd("echo", *["a"].flatten) }; __run_cmd { __cmd("echo", *["b"].flatten) }', code
  end

  # Backslash escapes in unquoted words (shell semantics: \X means literal X)

  def test_escaped_space_in_filename
    code = generate('rm a\\ b')
    assert_equal '__cmd("rm", *["a b"].flatten)', code
  end

  def test_escaped_space_with_path
    code = generate('ls /tmp/foo\\ bar')
    assert_equal '__cmd("ls", *["/tmp/foo bar"].flatten)', code
  end

  def test_multiple_escaped_spaces
    code = generate('cat a\\ b\\ c')
    assert_equal '__cmd("cat", *["a b c"].flatten)', code
  end

  def test_escaped_tab_in_unquoted_word
    code = generate("cat a\\\tb")
    # Tab is inspected as \t in Ruby string literal form
    assert_equal '__cmd("cat", *["a\tb"].flatten)', code
  end

  def test_escaped_dollar_prevents_variable_expansion
    code = generate('echo \\$HOME')
    assert_equal '__cmd("echo", *["$HOME"].flatten)', code
  end

  def test_escaped_backtick_prevents_command_substitution
    code = generate('echo \\`cmd\\`')
    assert_equal '__cmd("echo", *["`cmd`"].flatten)', code
  end

  def test_escaped_backslash_produces_single_backslash
    code = generate('echo a\\\\b')
    assert_equal '__cmd("echo", *["a\\\\b"].flatten)', code
  end

  def test_escaped_space_with_variable_in_word
    # \ before space + $VAR later: space is escaped, var still expands
    code = generate('echo a\\ $HOME')
    assert_equal '__cmd("echo", *["a #{__fetch_var("HOME")}"].flatten)', code
  end

  def test_single_quoted_preserves_backslash
    code = generate("echo 'a\\ b'")
    assert_equal '__cmd("echo", *["a\\\\ b"].flatten)', code
  end

  def test_double_quoted_backslash_before_special
    # In double quotes, \$ should become literal $
    code = generate('echo "\\$HOME"')
    assert_equal '__cmd("echo", *["$HOME"].flatten)', code
  end

  def test_double_quoted_backslash_before_non_special
    # In double quotes, \X for non-special X keeps the backslash
    code = generate('echo "a\\zb"')
    assert_equal '__cmd("echo", *["a\\\\zb"].flatten)', code
  end
end
