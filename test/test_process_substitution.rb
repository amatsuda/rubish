# frozen_string_literal: true

require_relative 'test_helper'

class TestProcessSubstitution < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_procsub_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    @repl.send(:cleanup_proc_sub_fifos) if @repl.instance_variable_get(:@proc_sub_fifos)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_lexer_proc_sub_in
    tokens = Rubish::Lexer.new('cat <(echo hello)').tokenize
    assert_equal :WORD, tokens[0].type
    assert_equal 'cat', tokens[0].value
    assert_equal :PROC_SUB_IN, tokens[1].type
    assert_equal 'echo hello', tokens[1].value
  end

  def test_lexer_proc_sub_out
    tokens = Rubish::Lexer.new('tee >(cat)').tokenize
    assert_equal :WORD, tokens[0].type
    assert_equal 'tee', tokens[0].value
    assert_equal :PROC_SUB_OUT, tokens[1].type
    assert_equal 'cat', tokens[1].value
  end

  def test_lexer_multiple_proc_sub
    tokens = Rubish::Lexer.new('diff <(ls) <(ls -a)').tokenize
    assert_equal :WORD, tokens[0].type
    assert_equal 'diff', tokens[0].value
    assert_equal :PROC_SUB_IN, tokens[1].type
    assert_equal 'ls', tokens[1].value
    assert_equal :PROC_SUB_IN, tokens[2].type
    assert_equal 'ls -a', tokens[2].value
  end

  def test_lexer_proc_sub_with_pipe
    tokens = Rubish::Lexer.new('cat <(ls | sort)').tokenize
    assert_equal :PROC_SUB_IN, tokens[1].type
    assert_equal 'ls | sort', tokens[1].value
  end

  # Parser tests
  def test_parser_proc_sub_in
    tokens = Rubish::Lexer.new('cat <(echo hello)').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'cat', ast.name
    assert_equal 1, ast.args.length
    assert_instance_of Rubish::AST::ProcessSubstitution, ast.args[0]
    assert_equal 'echo hello', ast.args[0].command
    assert_equal :in, ast.args[0].direction
  end

  def test_parser_proc_sub_out
    tokens = Rubish::Lexer.new('tee >(cat)').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'tee', ast.name
    assert_instance_of Rubish::AST::ProcessSubstitution, ast.args[0]
    assert_equal :out, ast.args[0].direction
  end

  # Codegen tests
  def test_codegen_proc_sub
    tokens = Rubish::Lexer.new('cat <(echo hello)').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__proc_sub/, code)
    assert_match(/:in/, code)
  end

  # Execution tests
  def test_simple_proc_sub_in
    execute("cat <(echo hello) > #{output_file}")
    sleep 0.3
    assert_equal "hello\n", File.read(output_file)
  end

  def test_proc_sub_with_multiple_lines
    execute("cat <(printf 'a\\nb\\nc\\n') > #{output_file}")
    sleep 0.3
    assert_equal "a\nb\nc\n", File.read(output_file)
  end

  def test_proc_sub_with_pipeline_inside
    execute("cat <(echo hello | tr a-z A-Z) > #{output_file}")
    sleep 0.3
    assert_equal "HELLO\n", File.read(output_file)
  end

  def test_two_proc_subs
    execute("diff <(echo a) <(echo a) > #{output_file}")
    sleep 0.5
    # diff with same content produces no output
    assert_equal '', File.read(output_file)
  end

  def test_two_proc_subs_different
    execute("diff <(echo a) <(echo b) > #{output_file} 2>&1; true")
    sleep 0.5
    result = File.read(output_file)
    assert_match(/< a/, result)
    assert_match(/> b/, result)
  end

  def test_wc_with_proc_sub
    execute("wc -l <(printf 'a\\nb\\nc\\n') > #{output_file}")
    sleep 0.3
    result = File.read(output_file).strip
    # wc -l output is "3" or "       3 /path/to/fifo"
    assert_match(/3/, result)
  end

  def test_proc_sub_with_sort
    execute("sort <(printf 'c\\na\\nb\\n') > #{output_file}")
    sleep 0.3
    assert_equal "a\nb\nc\n", File.read(output_file)
  end

  # Test that proc sub works with regular args
  def test_proc_sub_with_regular_args
    execute("cat -n <(echo hello) > #{output_file}")
    sleep 0.3
    result = File.read(output_file).strip
    assert_match(/1.*hello/, result)
  end
end
