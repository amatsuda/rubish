# frozen_string_literal: true

require_relative 'test_helper'

class TestIf < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_if_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_if_is_keyword
    tokens = Rubish::Lexer.new('if').tokenize
    assert_equal :IF, tokens.first.type
  end

  def test_then_is_keyword
    tokens = Rubish::Lexer.new('then').tokenize
    assert_equal :THEN, tokens.first.type
  end

  def test_else_is_keyword
    tokens = Rubish::Lexer.new('else').tokenize
    assert_equal :ELSE, tokens.first.type
  end

  def test_elif_is_keyword
    tokens = Rubish::Lexer.new('elif').tokenize
    assert_equal :ELIF, tokens.first.type
  end

  def test_fi_is_keyword
    tokens = Rubish::Lexer.new('fi').tokenize
    assert_equal :FI, tokens.first.type
  end

  def test_if_tokenization
    tokens = Rubish::Lexer.new('if test -f foo; then echo yes; fi').tokenize
    types = tokens.map(&:type)
    assert_equal [:IF, :WORD, :WORD, :WORD, :SEMICOLON, :THEN, :WORD, :WORD, :SEMICOLON, :FI], types
  end

  # Parser tests
  def test_simple_if_parsing
    tokens = Rubish::Lexer.new('if true; then echo yes; fi').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::If, ast
    assert_equal 1, ast.branches.length
    assert_nil ast.else_body
  end

  def test_if_else_parsing
    tokens = Rubish::Lexer.new('if true; then echo yes; else echo no; fi').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::If, ast
    assert_equal 1, ast.branches.length
    assert_not_nil ast.else_body
  end

  def test_if_elif_parsing
    tokens = Rubish::Lexer.new('if test -z x; then echo a; elif test -n x; then echo b; fi').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::If, ast
    assert_equal 2, ast.branches.length
    assert_nil ast.else_body
  end

  def test_if_elif_else_parsing
    tokens = Rubish::Lexer.new('if test 1 -eq 2; then echo a; elif test 1 -eq 1; then echo b; else echo c; fi').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::If, ast
    assert_equal 2, ast.branches.length
    assert_not_nil ast.else_body
  end

  # Execution tests - simple if
  def test_if_true_runs_body
    execute("if true; then echo yes > #{output_file}; fi")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_if_false_skips_body
    File.write(output_file, 'original')
    execute("if false; then echo yes > #{output_file}; fi")
    assert_equal 'original', File.read(output_file)
  end

  # Execution tests - if/else
  def test_if_else_true_branch
    execute("if true; then echo yes > #{output_file}; else echo no > #{output_file}; fi")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_if_else_false_branch
    execute("if false; then echo yes > #{output_file}; else echo no > #{output_file}; fi")
    assert_equal "no\n", File.read(output_file)
  end

  # Execution tests - test builtin
  def test_if_with_test_true
    execute("if test -n hello; then echo yes > #{output_file}; fi")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_if_with_test_false
    File.write(output_file, 'original')
    execute("if test -z hello; then echo yes > #{output_file}; fi")
    assert_equal 'original', File.read(output_file)
  end

  def test_if_with_bracket_syntax
    execute("if [ -n hello ]; then echo yes > #{output_file}; fi")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_if_with_string_comparison
    execute("if test foo = foo; then echo match > #{output_file}; fi")
    assert_equal "match\n", File.read(output_file)
  end

  def test_if_with_numeric_comparison
    execute("if test 5 -gt 3; then echo greater > #{output_file}; fi")
    assert_equal "greater\n", File.read(output_file)
  end

  # Execution tests - elif
  def test_elif_first_matches
    execute("if test 1 -eq 1; then echo first > #{output_file}; elif test 2 -eq 2; then echo second > #{output_file}; fi")
    assert_equal "first\n", File.read(output_file)
  end

  def test_elif_second_matches
    execute("if test 1 -eq 2; then echo first > #{output_file}; elif test 2 -eq 2; then echo second > #{output_file}; fi")
    assert_equal "second\n", File.read(output_file)
  end

  def test_elif_none_matches_no_else
    File.write(output_file, 'original')
    execute("if test 1 -eq 2; then echo first > #{output_file}; elif test 3 -eq 4; then echo second > #{output_file}; fi")
    assert_equal 'original', File.read(output_file)
  end

  def test_elif_with_else
    execute("if test 1 -eq 2; then echo first > #{output_file}; elif test 3 -eq 4; then echo second > #{output_file}; else echo default > #{output_file}; fi")
    assert_equal "default\n", File.read(output_file)
  end

  # Execution tests - elsif (Ruby-style)
  def test_elsif_is_keyword
    tokens = Rubish::Lexer.new('elsif').tokenize
    assert_equal :ELSIF, tokens.first.type
  end

  def test_if_elsif_parsing
    tokens = Rubish::Lexer.new('if test -z x; then echo a; elsif test -n x; then echo b; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::If, ast
    assert_equal 2, ast.branches.length
    assert_nil ast.else_body
  end

  def test_elsif_first_matches
    execute("if test 1 -eq 1; then echo first > #{output_file}; elsif test 2 -eq 2; then echo second > #{output_file}; end")
    assert_equal "first\n", File.read(output_file)
  end

  def test_elsif_second_matches
    execute("if test 1 -eq 2; then echo first > #{output_file}; elsif test 2 -eq 2; then echo second > #{output_file}; end")
    assert_equal "second\n", File.read(output_file)
  end

  def test_elsif_with_else
    execute("if test 1 -eq 2; then echo first > #{output_file}; elsif test 3 -eq 4; then echo second > #{output_file}; else echo default > #{output_file}; end")
    assert_equal "default\n", File.read(output_file)
  end

  def test_elsif_multiple_branches
    execute("if test 1 -eq 2; then echo first > #{output_file}; elsif test 2 -eq 3; then echo second > #{output_file}; elsif test 3 -eq 3; then echo third > #{output_file}; end")
    assert_equal "third\n", File.read(output_file)
  end

  # Execution tests - file tests
  def test_if_file_exists
    test_file = File.join(@tempdir, 'exists.txt')
    File.write(test_file, 'content')
    execute("if test -f #{test_file}; then echo yes > #{output_file}; fi")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_if_file_not_exists
    File.write(output_file, 'original')
    execute("if test -f /nonexistent/file; then echo yes > #{output_file}; fi")
    assert_equal 'original', File.read(output_file)
  end

  def test_if_dir_exists
    execute("if test -d #{@tempdir}; then echo yes > #{output_file}; fi")
    assert_equal "yes\n", File.read(output_file)
  end

  # Execution tests - multiple commands in body
  def test_if_multiple_commands_in_body
    execute("if true; then echo first > #{output_file}; echo second >> #{output_file}; fi")
    assert_equal "first\nsecond\n", File.read(output_file)
  end

  # Execution tests - nested if
  def test_nested_if
    execute("if true; then if test 1 -eq 1; then echo nested > #{output_file}; fi; fi")
    assert_equal "nested\n", File.read(output_file)
  end

  # Execution tests - condition with && and ||
  def test_if_with_and_condition
    execute("if true && true; then echo yes > #{output_file}; fi")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_if_with_and_condition_false
    File.write(output_file, 'original')
    execute("if true && false; then echo yes > #{output_file}; fi")
    assert_equal 'original', File.read(output_file)
  end

  def test_if_with_or_condition
    execute("if false || true; then echo yes > #{output_file}; fi")
    assert_equal "yes\n", File.read(output_file)
  end

  # Ruby-style if without 'then'
  def test_if_without_then
    execute("if true; echo yes > #{output_file}; end")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_if_else_without_then
    execute("if false; echo yes > #{output_file}; else echo no > #{output_file}; end")
    assert_equal "no\n", File.read(output_file)
  end

  def test_if_elif_without_then
    execute("if false; echo a > #{output_file}; elif true; echo b > #{output_file}; end")
    assert_equal "b\n", File.read(output_file)
  end

  def test_if_without_then_multiline
    script = File.join(@tempdir, 'if_no_then.sh')
    File.write(script, <<~SCRIPT)
      if true
        echo yes > #{output_file}
      end
    SCRIPT
    execute("source #{script}")
    assert_equal "yes\n", File.read(output_file)
  end
end
