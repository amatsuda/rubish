# frozen_string_literal: true

require_relative 'test_helper'

class TestUnless < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_unless_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_unless_is_keyword
    tokens = Rubish::Lexer.new('unless').tokenize
    assert_equal :UNLESS, tokens.first.type
  end

  def test_unless_tokenization
    tokens = Rubish::Lexer.new('unless false; echo yes; end').tokenize
    types = tokens.map(&:type)
    assert_equal [:UNLESS, :WORD, :SEMICOLON, :WORD, :WORD, :SEMICOLON, :WORD], types
  end

  def test_unless_with_then_tokenization
    tokens = Rubish::Lexer.new('unless false; then echo yes; end').tokenize
    types = tokens.map(&:type)
    assert_equal [:UNLESS, :WORD, :SEMICOLON, :THEN, :WORD, :WORD, :SEMICOLON, :WORD], types
  end

  # Parser tests
  def test_simple_unless_parsing
    tokens = Rubish::Lexer.new('unless false; echo yes; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Unless, ast
    assert_nil ast.else_body
  end

  def test_unless_with_then_parsing
    tokens = Rubish::Lexer.new('unless false; then echo yes; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Unless, ast
    assert_nil ast.else_body
  end

  def test_unless_else_parsing
    tokens = Rubish::Lexer.new('unless false; echo yes; else echo no; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Unless, ast
    assert_not_nil ast.else_body
  end

  def test_unless_multiple_commands_parsing
    tokens = Rubish::Lexer.new('unless false; echo a; echo b; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Unless, ast
    assert_instance_of Rubish::AST::List, ast.body
    assert_equal 2, ast.body.commands.length
  end

  # Execution tests - basic unless (redirect inside body to avoid compound redirect issues)
  def test_unless_false_runs_body
    execute("unless false; echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_unless_true_skips_body
    File.write(output_file, 'original')
    execute("unless true; echo yes > #{output_file}; end")
    assert_equal 'original', File.read(output_file)
  end

  # Execution tests - with else (redirect inside)
  def test_unless_false_with_else
    execute("unless false; echo yes > #{output_file}; else echo no > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_unless_true_with_else
    execute("unless true; echo yes > #{output_file}; else echo no > #{output_file}; end")
    assert_equal "no\n", File.read(output_file)
  end

  # Execution tests - with test command
  def test_unless_test_n_empty_string
    execute('unless test -n ""; echo empty > ' + output_file + '; end')
    assert_equal "empty\n", File.read(output_file)
  end

  def test_unless_test_n_non_empty_string
    execute('unless test -n "hello"; echo empty > ' + output_file + '; else echo notempty > ' + output_file + '; end')
    assert_equal "notempty\n", File.read(output_file)
  end

  def test_unless_test_f_nonexistent
    execute("unless test -f /nonexistent; echo notfound > #{output_file}; end")
    assert_equal "notfound\n", File.read(output_file)
  end

  # Execution tests - with optional 'then'
  def test_unless_with_then
    execute("unless false; then echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  # Execution tests - multiline via source
  def test_unless_multiline
    script = File.join(@tempdir, 'unless_test.sh')
    File.write(script, <<~SCRIPT)
      unless false
        echo yes > #{output_file}
      end
    SCRIPT
    execute("source #{script}")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_unless_else_multiline
    script = File.join(@tempdir, 'unless_else_test.sh')
    File.write(script, <<~SCRIPT)
      unless true
        echo yes > #{output_file}
      else
        echo no > #{output_file}
      end
    SCRIPT
    execute("source #{script}")
    assert_equal "no\n", File.read(output_file)
  end

  # Execution tests - nested (redirect inside)
  def test_nested_unless
    execute("unless false; unless true; echo inner > #{output_file}; else echo outer > #{output_file}; end; end")
    assert_equal "outer\n", File.read(output_file)
  end

  def test_unless_with_if_inside
    execute("unless false; if true; then echo yes > #{output_file}; fi; end")
    assert_equal "yes\n", File.read(output_file)
  end

  # Execution tests - with compound redirection
  def test_unless_with_compound_redirection
    execute("unless false; echo yes; end > #{output_file}")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_unless_else_with_compound_redirection
    execute("unless true; echo yes; else echo no; end > #{output_file}")
    assert_equal "no\n", File.read(output_file)
  end

  # Execution tests - with pipeline
  def test_unless_in_pipeline
    execute("unless false; echo HELLO; end | tr A-Z a-z > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  # Condition tests
  def test_unless_with_and_condition
    execute("unless true && true; echo no > #{output_file}; else echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_unless_with_or_condition
    execute("unless false || false; echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end
end
