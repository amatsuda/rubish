# frozen_string_literal: true

require_relative 'test_helper'

class TestFor < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_for_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_for_is_keyword
    tokens = Rubish::Lexer.new('for').tokenize
    assert_equal :FOR, tokens.first.type
  end

  def test_in_is_word
    tokens = Rubish::Lexer.new('in').tokenize
    assert_equal :WORD, tokens.first.type
  end

  # Parser tests
  def test_simple_for_parsing
    tokens = Rubish::Lexer.new('for x in a b c; do echo $x; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::For, ast
    assert_equal 'x', ast.variable
    assert_equal %w[a b c], ast.items
  end

  def test_for_in_if_parsing
    tokens = Rubish::Lexer.new('if true; then for x in a; do echo $x; done; fi').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::If, ast
    assert_instance_of Rubish::AST::For, ast.branches.first[1]
  end

  # Codegen tests
  def test_for_codegen
    tokens = Rubish::Lexer.new('for x in a b c; do echo $x; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__for_loop\("x", \["a", "b", "c"\]\.flatten\)/, code)
  end

  # Execution tests
  def test_for_sets_loop_variable
    ENV.delete('myvar')
    execute('for myvar in first second third; do true; done')
    assert_equal 'third', get_shell_var('myvar')
  end

  def test_in_as_argument
    execute("echo in > #{output_file}")
    assert_equal "in\n", File.read(output_file)
  end

  def test_for_simple_iteration
    execute("for x in a b c; do echo $x >> #{output_file}; done")
    assert_equal "a\nb\nc\n", File.read(output_file)
  end

  def test_for_in_script
    script = File.join(@tempdir, 'for.sh')
    File.write(script, <<~SCRIPT)
      for item in one two three; do
        echo $item >> #{output_file}
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "one\ntwo\nthree\n", File.read(output_file)
  end

  def test_for_nested
    script = File.join(@tempdir, 'nested.sh')
    File.write(script, <<~SCRIPT)
      for i in 1 2; do
        for j in a b; do
          echo "$i$j" >> #{output_file}
        done
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "1a\n1b\n2a\n2b\n", File.read(output_file)
  end
end
