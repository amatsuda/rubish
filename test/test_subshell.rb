# frozen_string_literal: true

require_relative 'test_helper'

class TestSubshell < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_subshell_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_lparen_token
    tokens = Rubish::Lexer.new('(').tokenize
    assert_equal :LPAREN, tokens.first.type
  end

  def test_parens_still_works_for_functions
    tokens = Rubish::Lexer.new('foo()').tokenize
    assert_equal :WORD, tokens[0].type
    assert_equal :PARENS, tokens[1].type
  end

  def test_subshell_tokenization
    tokens = Rubish::Lexer.new('(echo hello)').tokenize
    types = tokens.map(&:type)
    assert_equal [:LPAREN, :WORD, :WORD, :RPAREN], types
  end

  # Parser tests
  def test_simple_subshell_parsing
    tokens = Rubish::Lexer.new('(echo hello)').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Subshell, ast
    assert_instance_of Rubish::AST::Command, ast.body
  end

  def test_subshell_multiple_commands_parsing
    tokens = Rubish::Lexer.new('(echo a; echo b)').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Subshell, ast
    assert_instance_of Rubish::AST::List, ast.body
  end

  def test_subshell_with_redirect_parsing
    tokens = Rubish::Lexer.new('(echo hello) > /tmp/out').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Redirect, ast
    assert_instance_of Rubish::AST::Subshell, ast.command
  end

  # Codegen tests
  def test_subshell_codegen
    tokens = Rubish::Lexer.new('(echo hello)').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__subshell/, code)
  end

  # Execution tests
  def test_simple_subshell
    execute("(echo hello) > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_subshell_multiple_commands
    execute("(echo one; echo two) > #{output_file}")
    assert_equal "one\ntwo\n", File.read(output_file)
  end

  def test_subshell_cd_does_not_affect_parent
    original_dir = Dir.pwd
    execute('(cd /tmp)')
    assert_equal original_dir, Dir.pwd
  end

  def test_subshell_export_does_not_affect_parent
    ENV.delete('SUBSHELL_VAR')
    execute('(export SUBSHELL_VAR=value)')
    assert_nil ENV['SUBSHELL_VAR']
  end

  def test_subshell_inherits_parent_env
    ENV['PARENT_VAR'] = 'inherited'
    execute("(echo $PARENT_VAR) > #{output_file}")
    assert_equal "inherited\n", File.read(output_file)
  end

  def test_subshell_with_redirect
    execute("(echo hello; echo world) > #{output_file}")
    assert_equal "hello\nworld\n", File.read(output_file)
  end

  def test_subshell_in_pipeline
    execute("(echo HELLO) | tr A-Z a-z > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_pipeline_into_subshell
    execute("echo hello | (tr a-z A-Z) > #{output_file}")
    assert_equal "HELLO\n", File.read(output_file)
  end

  def test_subshell_with_loop
    execute("(for x in a b c; do echo $x; done) > #{output_file}")
    assert_equal "a\nb\nc\n", File.read(output_file)
  end

  def test_subshell_with_conditional
    execute("(if true; then echo yes; fi) > #{output_file}")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_nested_subshells
    execute("(echo outer; (echo inner)) > #{output_file}")
    assert_equal "outer\ninner\n", File.read(output_file)
  end

  def test_subshell_exit_status_success
    execute('(true)')
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_subshell_exit_status_failure
    execute('(false)')
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_subshell_in_script
    script = File.join(@tempdir, 'subshell.sh')
    File.write(script, <<~SCRIPT)
      export VAR=before
      (
        export VAR=inside
        echo $VAR > #{output_file}
      )
      echo $VAR >> #{output_file}
    SCRIPT

    execute("source #{script}")
    assert_equal "inside\nbefore\n", File.read(output_file)
  end

  def test_subshell_with_function_inside
    execute("(greet() { echo hi; }; greet) > #{output_file}")
    assert_equal "hi\n", File.read(output_file)
    # Function defined in subshell should not exist in parent
    assert_false @repl.functions.key?('greet')
  end
end
