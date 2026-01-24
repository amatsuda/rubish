# frozen_string_literal: true

require_relative 'test_helper'

class TestFunction < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_func_test')
    @original_env = ENV.to_h.dup
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
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
    # Includes source code as second parameter, params as third (nil for traditional syntax)
    assert_match(/__define_function\("greet", "echo hello", nil\)/, code)
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

  def test_function_dollar_at_no_args_unquoted
    # $@ with no args should expand to nothing, not empty string
    # This tests that commands don't receive spurious empty arguments
    execute('wrapper() { echo $#; }')
    execute("wrapper > #{output_file}")
    assert_equal "0\n", File.read(output_file)
  end

  def test_function_dollar_at_no_args_quoted
    # "$@" with no args should also expand to nothing
    execute('wrapper() { echo "$#"; }')
    execute("wrapper > #{output_file}")
    assert_equal "0\n", File.read(output_file)
  end

  def test_function_dollar_at_passes_args_to_inner
    # $@ should pass all args correctly to inner function
    execute('inner() { echo "got: $1 $2 $3"; }')
    execute('outer() { inner "$@"; }')
    execute("outer a b c > #{output_file}")
    assert_equal "got: a b c\n", File.read(output_file)
  end

  def test_function_dollar_at_no_args_passes_nothing
    # "$@" with no args should pass nothing to inner function
    execute('inner() { echo "argc=$#"; }')
    execute('outer() { inner "$@"; }')
    execute("outer > #{output_file}")
    assert_equal "argc=0\n", File.read(output_file)
  end

  def test_function_dollar_at_preserves_spaces_in_args
    # "$@" should preserve argument boundaries (args with spaces)
    execute('count_args() { echo $#; }')
    execute("count_args \"hello world\" foo > #{output_file}")
    assert_equal "2\n", File.read(output_file)
  end

  def test_function_dollar_at_in_string
    # $@ embedded in a string should join with spaces
    execute('show() { echo "args: $@"; }')
    execute("show a b c > #{output_file}")
    assert_equal "args: a b c\n", File.read(output_file)
  end

  def test_function_dollar_at_in_string_no_args
    # $@ in string with no args should be empty string
    execute('show() { echo "args: $@"; }')
    execute("show > #{output_file}")
    assert_equal "args: \n", File.read(output_file)
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

  def test_function_in_pipeline
    execute('shout() { echo HELLO; }')
    execute("shout | tr A-Z a-z > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_function_at_end_of_pipeline
    execute('upper() { tr a-z A-Z; }')
    execute("echo hello | upper > #{output_file}")
    assert_equal "HELLO\n", File.read(output_file)
  end

  def test_function_in_middle_of_pipeline
    execute('double() { while read line; do echo $line; echo $line; done; }')
    execute("echo hello | double | wc -l > #{output_file}")
    # wc output format differs between macOS (padded) and Linux (no padding)
    assert_equal '2', File.read(output_file).strip
  end

  def test_multiple_functions_in_pipeline
    execute('add_prefix() { while read line; do echo PREFIX:$line; done; }')
    execute('add_suffix() { while read line; do echo $line:SUFFIX; done; }')
    execute("echo test | add_prefix | add_suffix > #{output_file}")
    assert_equal "PREFIX:test:SUFFIX\n", File.read(output_file)
  end

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

  # FUNCNEST tests

  def test_funcnest_not_set_allows_nesting
    ENV.delete('FUNCNEST')
    # Define nested function calls
    execute('level3() { echo level3; }')
    execute('level2() { echo level2; level3; }')
    execute('level1() { echo level1; level2; }')
    execute("level1 > #{output_file}")
    assert_equal "level1\nlevel2\nlevel3\n", File.read(output_file)
  end

  def test_funcnest_allows_within_limit
    ENV['FUNCNEST'] = '5'
    execute('level3() { echo level3; }')
    execute('level2() { echo level2; level3; }')
    execute('level1() { echo level1; level2; }')
    execute("level1 > #{output_file}")
    assert_equal "level1\nlevel2\nlevel3\n", File.read(output_file)
  end

  def test_funcnest_blocks_exceeding_limit
    ENV['FUNCNEST'] = '3'
    # Recursive function that will exceed limit
    execute('recurse() { echo $1; recurse next; }')
    stderr = capture_stderr { execute("recurse 1 > #{output_file}") }
    output = File.read(output_file)
    # First 3 calls succeed (depths 1, 2, 3), 4th call is blocked
    lines = output.strip.split("\n")
    assert_equal 3, lines.length
    assert_match(/maximum function nesting level exceeded/, stderr)
  end

  def test_funcnest_one
    ENV['FUNCNEST'] = '1'
    execute('outer() { echo outer; inner; }')
    execute('inner() { echo inner; }')
    stderr = capture_stderr { execute("outer > #{output_file}") }
    # outer runs (depth 1), but inner would be depth 2
    output = File.read(output_file)
    assert_equal "outer\n", output
    assert_match(/maximum function nesting level exceeded/, stderr)
  end

  def test_funcnest_zero_means_no_limit
    ENV['FUNCNEST'] = '0'
    execute('level3() { echo level3; }')
    execute('level2() { echo level2; level3; }')
    execute('level1() { echo level1; level2; }')
    execute("level1 > #{output_file}")
    # Zero means no limit
    assert_equal "level1\nlevel2\nlevel3\n", File.read(output_file)
  end

  def test_funcnest_negative_means_no_limit
    ENV['FUNCNEST'] = '-1'
    execute('level3() { echo level3; }')
    execute('level2() { echo level2; level3; }')
    execute('level1() { echo level1; level2; }')
    execute("level1 > #{output_file}")
    assert_equal "level1\nlevel2\nlevel3\n", File.read(output_file)
  end

  def test_funcnest_empty_string
    ENV['FUNCNEST'] = ''
    execute('level3() { echo level3; }')
    execute('level2() { echo level2; level3; }')
    execute('level1() { echo level1; level2; }')
    execute("level1 > #{output_file}")
    assert_equal "level1\nlevel2\nlevel3\n", File.read(output_file)
  end

  def test_funcnest_non_numeric
    ENV['FUNCNEST'] = 'abc'
    execute('level3() { echo level3; }')
    execute('level2() { echo level2; level3; }')
    execute('level1() { echo level1; level2; }')
    execute("level1 > #{output_file}")
    # to_i returns 0 for non-numeric, so no limit
    assert_equal "level1\nlevel2\nlevel3\n", File.read(output_file)
  end

  def test_funcnest_mutual_recursion
    ENV['FUNCNEST'] = '4'
    execute('ping() { echo ping; pong; }')
    execute('pong() { echo pong; ping; }')
    stderr = capture_stderr { execute("ping > #{output_file}") }
    # ping(1) -> pong(2) -> ping(3) -> pong(4) -> ping would be 5, blocked
    output = File.read(output_file)
    assert_equal "ping\npong\nping\npong\n", output
    assert_match(/maximum function nesting level exceeded/, stderr)
  end

  def test_funcnest_returns_false_on_exceed
    ENV['FUNCNEST'] = '1'
    execute('outer() { inner && echo "inner succeeded" || echo "inner failed"; }')
    execute('inner() { echo inner; }')
    capture_stderr { execute("outer > #{output_file}") }
    output = File.read(output_file)
    assert_match(/inner failed/, output)
  end

  def test_funcnest_exact_limit
    ENV['FUNCNEST'] = '2'
    execute('level2() { echo level2; }')
    execute('level1() { echo level1; level2; }')
    execute("level1 > #{output_file}")
    # Exactly 2 levels should work
    assert_equal "level1\nlevel2\n", File.read(output_file)
  end

  def test_funcnest_error_message_includes_function_name
    ENV['FUNCNEST'] = '1'
    execute('myfunc() { myfunc; }')
    stderr = capture_stderr { execute('myfunc') }
    assert_match(/myfunc/, stderr)
    assert_match(/maximum function nesting level exceeded/, stderr)
  end

  # Ruby-style def keyword tests

  def test_def_is_keyword
    tokens = Rubish::Lexer.new('def').tokenize
    assert_equal :DEF, tokens.first.type
  end

  def test_def_tokenization
    tokens = Rubish::Lexer.new('def greet; echo hello; end').tokenize
    types = tokens.map(&:type)
    assert_equal [:DEF, :WORD, :SEMICOLON, :WORD, :WORD, :SEMICOLON, :WORD], types
  end

  def test_def_parsing
    tokens = Rubish::Lexer.new('def greet; echo hello; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Function, ast
    assert_equal 'greet', ast.name
  end

  def test_def_with_parens_parsing
    tokens = Rubish::Lexer.new('def greet(); echo hello; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Function, ast
    assert_equal 'greet', ast.name
  end

  def test_def_multiple_commands_parsing
    tokens = Rubish::Lexer.new('def myfunc; echo a; echo b; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Function, ast
    assert_instance_of Rubish::AST::List, ast.body
    assert_equal 2, ast.body.commands.length
  end

  def test_def_simple_definition
    execute('def greet; echo hello; end')
    assert @repl.functions.key?('greet')
  end

  def test_def_simple_call
    execute('def greet; echo hello; end')
    execute("greet > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_def_with_params
    execute('def say_hello; echo Hello $1; end')
    execute("say_hello World > #{output_file}")
    assert_equal "Hello World\n", File.read(output_file)
  end

  def test_def_multiline
    script = File.join(@tempdir, 'def_func.sh')
    File.write(script, <<~SCRIPT)
      def greet
        echo Hello $1
      end
      greet World > #{output_file}
    SCRIPT

    execute("source #{script}")
    assert_equal "Hello World\n", File.read(output_file)
  end

  def test_def_with_loop
    execute('def countdown; for n in 3 2 1; do echo $n >> ' + output_file + '; done; end')
    execute('countdown')
    assert_equal "3\n2\n1\n", File.read(output_file)
  end

  def test_def_with_conditional
    execute('def check_arg; if test -n $1; then echo yes; else echo no; fi; end')
    execute("check_arg hello > #{output_file}")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_def_nested_end
    # def with nested loops using 'end'
    execute('def multi_loop; for i in 1 2; do for j in a b; do echo $i$j >> ' + output_file + '; end; end; end')
    execute('multi_loop')
    assert_equal "1a\n1b\n2a\n2b\n", File.read(output_file)
  end

  def test_def_in_pipeline
    execute('def shout; echo HELLO; end')
    execute("shout | tr A-Z a-z > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  # Ruby-style def with named parameters
  def test_def_with_named_param
    execute('def greet(name); echo Hello $name; end')
    execute("greet World > #{output_file}")
    assert_equal "Hello World\n", File.read(output_file)
  end

  def test_def_with_multiple_named_params
    execute('def greet(greeting, name); echo $greeting $name; end')
    execute("greet Hello World > #{output_file}")
    assert_equal "Hello World\n", File.read(output_file)
  end

  def test_def_named_params_are_local
    execute('name=Outer')
    execute('def greet(name); echo $name; end')
    execute("greet Inner > #{output_file}")
    # name should be restored after function returns
    execute("echo $name >> #{output_file}")
    assert_equal "Inner\nOuter\n", File.read(output_file)
  end

  def test_def_named_params_with_positional_still_work
    # Both named params and $1, $2 should work
    execute('def greet(name); echo Hello $name and $1; end')
    execute("greet World > #{output_file}")
    assert_equal "Hello World and World\n", File.read(output_file)
  end

  def test_def_named_params_empty_parens
    # Empty parens should work like no parens
    execute('def greet(); echo Hello $1; end')
    execute("greet World > #{output_file}")
    assert_equal "Hello World\n", File.read(output_file)
  end

  def test_def_named_params_codegen
    tokens = Rubish::Lexer.new('def greet(name); echo $name; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    # Should include params array
    assert_match(/__define_function\("greet", "[^"]+", \["name"\]\)/, code)
  end

  # Ruby-style splat params (*args)
  def test_def_splat_param
    execute('def log(*args); echo $args; end')
    execute("log --oneline -3 > #{output_file}")
    assert_equal "--oneline -3\n", File.read(output_file)
  end

  def test_def_splat_param_no_args
    # Splat with no args should not pass empty string
    execute('inner() { echo "argc=$#"; }')
    execute('def outer(*args); inner $args; end')
    execute("outer > #{output_file}")
    assert_equal "argc=0\n", File.read(output_file)
  end

  def test_def_splat_param_passes_args_to_inner
    execute('inner() { echo "got: $1 $2 $3"; }')
    execute('def outer(*args); inner $args; end')
    execute("outer a b c > #{output_file}")
    assert_equal "got: a b c\n", File.read(output_file)
  end

  def test_def_splat_with_leading_params
    execute('def greet(greeting, *names); echo $greeting $names; end')
    execute("greet Hello Alice Bob > #{output_file}")
    assert_equal "Hello Alice Bob\n", File.read(output_file)
  end

  def test_def_splat_in_string
    # $args in string should join with spaces
    execute('def show(*args); echo "args: $args"; end')
    execute("show a b c > #{output_file}")
    assert_equal "args: a b c\n", File.read(output_file)
  end

  def test_def_splat_codegen
    tokens = Rubish::Lexer.new('def log(*args); echo $args; end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    # Should include splat param
    assert_match(/__define_function\("log", "[^"]+", \["\*args"\]\)/, code)
  end

  # Test that functions are available in command substitution
  # Regression test: previously $(func) would spawn /bin/sh which didn't have the function
  def test_function_in_command_substitution
    execute('greet() { echo hello; }')
    execute('result=$(greet)')
    assert_equal 'hello', get_shell_var('result')
  end

  def test_function_with_args_in_command_substitution
    execute('say() { echo "saying: $1"; }')
    execute('result=$(say world)')
    assert_equal 'saying: world', get_shell_var('result')
  end

  def test_function_in_nested_command_substitution
    execute('inner() { echo nested; }')
    execute('outer() { echo $(inner); }')
    execute('result=$(outer)')
    assert_equal 'nested', get_shell_var('result')
  end

  def test_function_in_backtick_substitution
    execute('greet() { echo hello; }')
    execute('result=`greet`')
    assert_equal 'hello', get_shell_var('result')
  end
end
