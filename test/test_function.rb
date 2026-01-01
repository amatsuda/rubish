# frozen_string_literal: true

require_relative 'test_helper'

class TestFunction < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_func_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_function_is_keyword
    tokens = Rubish::Lexer.new('function').tokenize
    assert_equal :FUNCTION, tokens.first.type
  end

  def test_parens_token
    tokens = Rubish::Lexer.new('foo()').tokenize
    assert_equal :WORD, tokens[0].type
    assert_equal :PARENS, tokens[1].type
    assert_equal '()', tokens[1].value
  end

  def test_function_keyword_tokenization
    tokens = Rubish::Lexer.new('function greet { echo hello; }').tokenize
    types = tokens.map(&:type)
    assert_equal [:FUNCTION, :WORD, :LBRACE, :WORD, :WORD, :SEMICOLON, :RBRACE], types
  end

  def test_parens_syntax_tokenization
    tokens = Rubish::Lexer.new('greet() { echo hello; }').tokenize
    types = tokens.map(&:type)
    assert_equal [:WORD, :PARENS, :LBRACE, :WORD, :WORD, :SEMICOLON, :RBRACE], types
  end

  # Parser tests
  def test_function_keyword_parsing
    tokens = Rubish::Lexer.new('function greet { echo hello; }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Function, ast
    assert_equal 'greet', ast.name
    assert_instance_of Rubish::AST::Command, ast.body
  end

  def test_parens_syntax_parsing
    tokens = Rubish::Lexer.new('greet() { echo hello; }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Function, ast
    assert_equal 'greet', ast.name
  end

  def test_function_multiple_commands
    tokens = Rubish::Lexer.new('myfunc() { echo a; echo b; }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Function, ast
    assert_instance_of Rubish::AST::List, ast.body
    assert_equal 2, ast.body.commands.length
  end

  # Codegen tests
  def test_function_codegen
    tokens = Rubish::Lexer.new('greet() { echo hello; }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__define_function\("greet"\)/, code)
  end

  # Execution tests
  def test_simple_function_definition
    execute('greet() { echo hello; }')
    assert @repl.functions.key?('greet')
  end

  def test_function_keyword_definition
    execute('function myfunc { echo test; }')
    assert @repl.functions.key?('myfunc')
  end

  def test_function_call
    execute('greet() { echo hello; }')
    execute("greet > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_function_with_positional_params
    execute('say_hello() { echo Hello $1; }')
    execute("say_hello World > #{output_file}")
    assert_equal "Hello World\n", File.read(output_file)
  end

  def test_function_with_multiple_params
    execute('greet_all() { echo $1 $2 $3; }')
    execute("greet_all Alice Bob Carol > #{output_file}")
    assert_equal "Alice Bob Carol\n", File.read(output_file)
  end

  def test_function_param_count
    execute('count_params() { echo $#; }')
    execute("count_params a b c > #{output_file}")
    assert_equal "3\n", File.read(output_file)
  end

  def test_function_all_params
    execute('show_all() { echo $@; }')
    execute("show_all one two three > #{output_file}")
    assert_equal "one two three\n", File.read(output_file)
  end

  def test_function_preserves_caller_params
    @repl.positional_params = ['outer1', 'outer2']
    execute('myfunc() { echo inner $1; }')
    execute("myfunc arg1 > #{output_file}")
    # Caller's params should be preserved after function returns
    assert_equal ['outer1', 'outer2'], @repl.positional_params
  end

  def test_function_with_loop
    execute('countdown() { for n in 3 2 1; do echo $n >> ' + output_file + '; done; }')
    execute('countdown')
    assert_equal "3\n2\n1\n", File.read(output_file)
  end

  def test_function_with_conditional
    execute('check_arg() { if test -n $1; then echo yes; else echo no; fi; }')
    execute("check_arg hello > #{output_file}")
    assert_equal "yes\n", File.read(output_file)
  end

  # TODO: Functions in pipelines require changes to the Pipeline class
  # def test_function_in_pipeline
  #   execute('shout() { echo HELLO; }')
  #   execute("shout | tr A-Z a-z > #{output_file}")
  #   assert_equal "hello\n", File.read(output_file)
  # end

  def test_nested_function_call
    execute('inner() { echo inside; }')
    execute('outer() { inner; }')
    execute("outer > #{output_file}")
    assert_equal "inside\n", File.read(output_file)
  end

  def test_function_in_script
    script = File.join(@tempdir, 'func.sh')
    File.write(script, <<~SCRIPT)
      greet() {
        echo Hello $1
      }
      greet World > #{output_file}
    SCRIPT

    execute("source #{script}")
    assert_equal "Hello World\n", File.read(output_file)
  end

  def test_function_redefinition
    execute('myfunc() { echo first; }')
    execute('myfunc() { echo second; }')
    execute("myfunc > #{output_file}")
    assert_equal "second\n", File.read(output_file)
  end

  def test_function_multiple_body_commands
    execute('multi() { echo one; echo two; echo three; }')
    execute("multi > #{output_file}")
    assert_equal "one\ntwo\nthree\n", File.read(output_file)
  end

  def test_function_with_variable
    ENV['MSG'] = 'hello'
    execute('showmsg() { echo $MSG; }')
    execute("showmsg > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end
end
