# frozen_string_literal: true

require_relative 'test_helper'

class TestWhile < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_while_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_while_is_keyword
    tokens = Rubish::Lexer.new('while').tokenize
    assert_equal :WHILE, tokens.first.type
  end

  def test_do_is_word
    # 'do' should be a WORD token (not keyword) for flexibility
    tokens = Rubish::Lexer.new('do').tokenize
    assert_equal :WORD, tokens.first.type
  end

  def test_done_is_word
    # 'done' should be a WORD token (not keyword) for flexibility
    tokens = Rubish::Lexer.new('done').tokenize
    assert_equal :WORD, tokens.first.type
  end

  def test_while_tokenization
    tokens = Rubish::Lexer.new('while test -n x; do echo y; done').tokenize
    types = tokens.map(&:type)
    assert_equal [:WHILE, :WORD, :WORD, :WORD, :SEMICOLON, :WORD, :WORD, :WORD, :SEMICOLON, :WORD], types
  end

  # Parser tests
  def test_simple_while_parsing
    tokens = Rubish::Lexer.new('while true; do echo yes; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::While, ast
    assert_not_nil ast.condition
    assert_not_nil ast.body
  end

  def test_while_with_test_condition
    tokens = Rubish::Lexer.new('while test -n x; do echo y; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::While, ast
  end

  def test_while_multiple_body_commands
    tokens = Rubish::Lexer.new('while true; do echo a; echo b; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::While, ast
    assert_instance_of Rubish::AST::List, ast.body
  end

  # Codegen tests
  def test_while_codegen
    tokens = Rubish::Lexer.new('while true; do echo yes; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/while __condition/, code)
    assert_match(/__cmd\("echo", "yes"\)/, code)
  end

  # Execution tests - condition that is always false (no iterations)
  def test_while_false_never_runs
    script = File.join(@tempdir, 'false.sh')
    File.write(script, <<~SCRIPT)
      echo before > #{output_file}
      while false; do
        echo inside >> #{output_file}
      done
      echo after >> #{output_file}
    SCRIPT

    execute("source #{script}")

    content = File.read(output_file)
    assert_match(/before/, content)
    assert_match(/after/, content)
    assert_no_match(/inside/, content)
  end

  def test_while_test_z_nonempty_never_runs
    script = File.join(@tempdir, 'z.sh')
    File.write(script, <<~SCRIPT)
      echo start > #{output_file}
      while test -z nonempty; do
        echo loop >> #{output_file}
      done
      echo end >> #{output_file}
    SCRIPT

    execute("source #{script}")

    content = File.read(output_file)
    assert_match(/start/, content)
    assert_match(/end/, content)
    assert_no_match(/loop/, content)
  end

  def test_while_numeric_compare_false
    script = File.join(@tempdir, 'num.sh')
    File.write(script, <<~SCRIPT)
      echo start > #{output_file}
      while test 5 -gt 10; do
        echo loop >> #{output_file}
      done
      echo end >> #{output_file}
    SCRIPT

    execute("source #{script}")

    content = File.read(output_file)
    assert_match(/start/, content)
    assert_match(/end/, content)
    assert_no_match(/loop/, content)
  end

  # Test that 'done' and 'do' can be used as regular command arguments
  def test_done_as_argument
    execute("echo done > #{output_file}")
    assert_equal "done\n", File.read(output_file)
  end

  def test_do_as_argument
    execute("echo do > #{output_file}")
    assert_equal "do\n", File.read(output_file)
  end

  # Test nested structure parsing
  def test_while_in_if_parsing
    tokens = Rubish::Lexer.new('if true; then while false; do echo x; done; fi').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::If, ast
    assert_instance_of Rubish::AST::While, ast.branches.first[1]
  end

  def test_if_in_while_parsing
    tokens = Rubish::Lexer.new('while false; do if true; then echo x; fi; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::While, ast
    assert_instance_of Rubish::AST::If, ast.body
  end

  # Test while in if execution (false condition, no loop)
  def test_while_in_if_execution
    script = File.join(@tempdir, 'while_in_if.sh')
    File.write(script, <<~SCRIPT)
      if true; then
        echo before > #{output_file}
        while false; do
          echo loop >> #{output_file}
        done
        echo after >> #{output_file}
      fi
    SCRIPT

    execute("source #{script}")

    content = File.read(output_file)
    assert_match(/before/, content)
    assert_match(/after/, content)
    assert_no_match(/loop/, content)
  end

  # Test if in while execution (false condition, no loop)
  def test_if_in_while_execution
    script = File.join(@tempdir, 'if_in_while.sh')
    File.write(script, <<~SCRIPT)
      echo start > #{output_file}
      while test 1 -gt 2; do
        if true; then
          echo inside >> #{output_file}
        fi
      done
      echo end >> #{output_file}
    SCRIPT

    execute("source #{script}")

    content = File.read(output_file)
    assert_match(/start/, content)
    assert_match(/end/, content)
    assert_no_match(/inside/, content)
  end
end
