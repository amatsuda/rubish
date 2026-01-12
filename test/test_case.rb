# frozen_string_literal: true

require_relative 'test_helper'

class TestCase < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_case_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_case_is_keyword
    tokens = Rubish::Lexer.new('case').tokenize
    assert_equal :CASE, tokens.first.type
  end

  def test_esac_is_keyword
    tokens = Rubish::Lexer.new('esac').tokenize
    assert_equal :ESAC, tokens.first.type
  end

  def test_double_semi_token
    tokens = Rubish::Lexer.new(';;').tokenize
    assert_equal :DOUBLE_SEMI, tokens.first.type
    assert_equal ';;', tokens.first.value
  end

  def test_rparen_token
    tokens = Rubish::Lexer.new(')').tokenize
    assert_equal :RPAREN, tokens.first.type
  end

  def test_case_tokenization
    tokens = Rubish::Lexer.new('case $x in foo) echo yes;; esac').tokenize
    types = tokens.map(&:type)
    assert_equal [:CASE, :WORD, :WORD, :WORD, :RPAREN, :WORD, :WORD, :DOUBLE_SEMI, :ESAC], types
  end

  # Parser tests
  def test_case_parsing
    tokens = Rubish::Lexer.new('case $x in foo) echo yes;; esac').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Case, ast
    assert_equal '$x', ast.word
    assert_equal 1, ast.branches.length
    patterns, _body = ast.branches.first
    assert_equal ['foo'], patterns
  end

  def test_case_multiple_patterns_parsing
    tokens = Rubish::Lexer.new('case $x in foo|bar|baz) echo match;; esac').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Case, ast
    patterns, _body = ast.branches.first
    assert_equal ['foo', 'bar', 'baz'], patterns
  end

  def test_case_multiple_branches_parsing
    tokens = Rubish::Lexer.new('case $x in a) echo A;; b) echo B;; esac').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_equal 2, ast.branches.length
  end

  # Codegen tests
  def test_case_codegen
    tokens = Rubish::Lexer.new('case $x in foo) echo yes;; esac').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__case_word/, code)
    assert_match(/__case_match/, code)
  end

  # Execution tests
  def test_case_simple_match
    ENV['x'] = 'foo'
    execute("case $x in foo) echo matched > #{output_file};; esac")
    assert_equal "matched\n", File.read(output_file)
  end

  def test_case_no_match
    ENV['x'] = 'bar'
    File.write(output_file, '')  # Create empty file
    execute("case $x in foo) echo matched > #{output_file};; esac")
    assert_equal '', File.read(output_file)
  end

  def test_case_multiple_patterns
    ENV['x'] = 'bar'
    execute("case $x in foo|bar|baz) echo matched > #{output_file};; esac")
    assert_equal "matched\n", File.read(output_file)
  end

  def test_case_multiple_branches
    ENV['x'] = 'b'
    execute("case $x in a) echo A > #{output_file};; b) echo B > #{output_file};; esac")
    assert_equal "B\n", File.read(output_file)
  end

  def test_case_wildcard_star
    ENV['x'] = 'hello'
    execute("case $x in hell*) echo matched > #{output_file};; esac")
    assert_equal "matched\n", File.read(output_file)
  end

  def test_case_wildcard_question
    ENV['x'] = 'cat'
    execute("case $x in c?t) echo matched > #{output_file};; esac")
    assert_equal "matched\n", File.read(output_file)
  end

  def test_case_wildcard_bracket
    ENV['x'] = 'bat'
    execute("case $x in [bcr]at) echo matched > #{output_file};; esac")
    assert_equal "matched\n", File.read(output_file)
  end

  def test_case_default_pattern
    ENV['x'] = 'unknown'
    execute("case $x in foo) echo foo;; *) echo default > #{output_file};; esac")
    assert_equal "default\n", File.read(output_file)
  end

  def test_case_first_match_wins
    ENV['x'] = 'foo'
    execute("case $x in foo) echo first > #{output_file};; foo) echo second > #{output_file};; esac")
    assert_equal "first\n", File.read(output_file)
  end

  def test_case_with_multiple_commands
    ENV['x'] = 'yes'
    execute("case $x in yes) echo one > #{output_file}; echo two >> #{output_file};; esac")
    assert_equal "one\ntwo\n", File.read(output_file)
  end

  def test_case_in_script
    script = File.join(@tempdir, 'case.sh')
    File.write(script, <<~SCRIPT)
      case $1 in
        start)
          echo starting > #{output_file}
          ;;
        stop)
          echo stopping > #{output_file}
          ;;
        *)
          echo unknown > #{output_file}
          ;;
      esac
    SCRIPT

    execute("source #{script} start")
    assert_equal "starting\n", File.read(output_file)

    execute("source #{script} stop")
    assert_equal "stopping\n", File.read(output_file)

    execute("source #{script} other")
    assert_equal "unknown\n", File.read(output_file)
  end

  def test_case_variable_in_pattern
    ENV['pattern'] = 'foo'
    ENV['x'] = 'foo'
    execute("case $x in $pattern) echo matched > #{output_file};; esac")
    assert_equal "matched\n", File.read(output_file)
  end

  # Ruby-style case-when tests

  # Lexer tests
  def test_when_is_keyword
    tokens = Rubish::Lexer.new('when').tokenize
    assert_equal :WHEN, tokens.first.type
  end

  def test_case_when_tokenization
    tokens = Rubish::Lexer.new('case foo when foo; echo yes; end').tokenize
    types = tokens.map(&:type)
    assert_equal [:CASE, :WORD, :WHEN, :WORD, :SEMICOLON, :WORD, :WORD, :SEMICOLON, :WORD], types
  end

  # Parser tests
  def test_case_when_parsing
    tokens = Rubish::Lexer.new('case foo when foo; echo yes; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Case, ast
    assert_equal 'foo', ast.word
    assert_equal 1, ast.branches.length
    patterns, _body, _terminator = ast.branches.first
    assert_equal ['foo'], patterns
  end

  def test_case_when_multiple_patterns_parsing
    tokens = Rubish::Lexer.new('case x when foo | bar; echo yes; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    patterns, _body, _terminator = ast.branches.first
    assert_equal ['foo', 'bar'], patterns
  end

  def test_case_when_multiple_patterns_comma_parsing
    tokens = Rubish::Lexer.new('case x when foo, bar; echo yes; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    patterns, _body, _terminator = ast.branches.first
    assert_equal ['foo', 'bar'], patterns
  end

  def test_case_when_multiple_branches_parsing
    tokens = Rubish::Lexer.new('case x when a; echo A; when b; echo B; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_equal 2, ast.branches.length
  end

  def test_case_when_with_else_parsing
    tokens = Rubish::Lexer.new('case x when a; echo A; else echo default; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_equal 2, ast.branches.length
    patterns, _body, _terminator = ast.branches.last
    assert_equal ['*'], patterns
  end

  # Execution tests
  def test_case_when_simple_match
    execute("case foo when foo; echo matched > #{output_file}; end")
    assert_equal "matched\n", File.read(output_file)
  end

  def test_case_when_no_match
    File.write(output_file, '')
    execute("case bar when foo; echo matched > #{output_file}; end")
    assert_equal '', File.read(output_file)
  end

  def test_case_when_variable
    ENV['x'] = 'hello'
    execute("case $x when hello; echo matched > #{output_file}; end")
    assert_equal "matched\n", File.read(output_file)
  end

  def test_case_when_multiple_patterns
    execute("case bar when foo | bar; echo matched > #{output_file}; end")
    assert_equal "matched\n", File.read(output_file)
  end

  def test_case_when_multiple_branches
    execute("case b when a; echo A > #{output_file}; when b; echo B > #{output_file}; end")
    assert_equal "B\n", File.read(output_file)
  end

  def test_case_when_with_else
    execute("case unknown when foo; echo foo > #{output_file}; else echo default > #{output_file}; end")
    assert_equal "default\n", File.read(output_file)
  end

  def test_case_when_wildcard
    execute("case hello when hell*; echo matched > #{output_file}; end")
    assert_equal "matched\n", File.read(output_file)
  end

  def test_case_when_first_match_wins
    execute("case foo when foo; echo first > #{output_file}; when foo; echo second > #{output_file}; end")
    assert_equal "first\n", File.read(output_file)
  end

  def test_case_when_multiple_commands
    execute("case yes when yes; echo one > #{output_file}; echo two >> #{output_file}; end")
    assert_equal "one\ntwo\n", File.read(output_file)
  end

  def test_case_when_in_script
    script = File.join(@tempdir, 'case_when.sh')
    File.write(script, <<~SCRIPT)
      case $1
        when start
          echo starting > #{output_file}
        when stop
          echo stopping > #{output_file}
        else
          echo unknown > #{output_file}
      end
    SCRIPT

    execute("source #{script} start")
    assert_equal "starting\n", File.read(output_file)

    execute("source #{script} stop")
    assert_equal "stopping\n", File.read(output_file)

    execute("source #{script} other")
    assert_equal "unknown\n", File.read(output_file)
  end
end
