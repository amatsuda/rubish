# frozen_string_literal: true

require_relative 'test_helper'

class TestSelect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_select_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.delete('PS3')
    ENV.delete('REPLY')
    ENV.delete('choice')
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_select_is_keyword
    tokens = Rubish::Lexer.new('select').tokenize
    assert_equal :SELECT, tokens.first.type
  end

  def test_select_in_word_context
    # 'select' as standalone should be keyword
    tokens = Rubish::Lexer.new('select choice in').tokenize
    assert_equal :SELECT, tokens[0].type
    assert_equal :WORD, tokens[1].type
  end

  # Parser tests
  def test_simple_select_parsing
    tokens = Rubish::Lexer.new('select x in a b c; do echo $x; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Select, ast
    assert_equal 'x', ast.variable
    assert_equal %w[a b c], ast.items
  end

  def test_select_with_multiple_items
    tokens = Rubish::Lexer.new('select opt in option1 option2 option3 quit; do echo $opt; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Select, ast
    assert_equal 'opt', ast.variable
    assert_equal %w[option1 option2 option3 quit], ast.items
  end

  def test_select_parsing_with_newline_do
    # select with newline before do (like for)
    tokens = Rubish::Lexer.new('select x in a b c; do echo $x; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Select, ast
  end

  def test_select_body_is_command
    tokens = Rubish::Lexer.new('select x in a b; do echo $x; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Command, ast.body
    assert_equal 'echo', ast.body.name
  end

  def test_select_body_is_list
    tokens = Rubish::Lexer.new('select x in a b; do echo $x; echo done; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::List, ast.body
    assert_equal 2, ast.body.commands.length
  end

  def test_select_in_if_parsing
    tokens = Rubish::Lexer.new('if true; then select x in a; do echo $x; done; fi').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::If, ast
    assert_instance_of Rubish::AST::Select, ast.branches.first[1]
  end

  # Codegen tests
  def test_select_codegen
    tokens = Rubish::Lexer.new('select x in a b c; do echo $x; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__select_loop\("x", \["a", "b", "c"\]\.flatten\)/, code)
  end

  def test_select_codegen_generates_break_loop
    tokens = Rubish::Lexer.new('select x in a b c; do echo $x; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/catch\(:break_loop\)/, code)
  end

  def test_select_codegen_generates_continue_loop
    tokens = Rubish::Lexer.new('select x in a b c; do echo $x; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/catch\(:continue_loop\)/, code)
  end

  # Unit tests for helper methods
  def test_display_select_menu
    output = StringIO.new
    $stdout = output
    @repl.send(:display_select_menu, %w[apple banana cherry])
    $stdout = STDOUT

    expected = "1) apple\n2) banana\n3) cherry\n"
    assert_equal expected, output.string
  end

  def test_display_select_menu_with_padding
    output = StringIO.new
    $stdout = output
    items = (1..10).map { |i| "item#{i}" }
    @repl.send(:display_select_menu, items)
    $stdout = STDOUT

    lines = output.string.lines
    # First item should be right-justified like " 1) item1"
    assert_match(/\s*1\) item1/, lines[0])
    # Last item should be "10) item10"
    assert_match(/10\) item10/, lines[9])
  end

  def test_select_loop_sets_reply
    # Simulate stdin with '1' input then EOF
    old_stdin = $stdin
    $stdin = StringIO.new("1\n")

    # Suppress menu output
    old_stdout = $stdout
    $stdout = StringIO.new

    ENV.delete('REPLY')
    @repl.send(:__select_loop, 'choice', %w[a b c]) { }
    $stdout = old_stdout
    $stdin = old_stdin

    assert_equal '1', get_shell_var('REPLY')
  end

  def test_select_loop_sets_variable_for_valid_selection
    old_stdin = $stdin
    $stdin = StringIO.new("2\n")

    old_stdout = $stdout
    $stdout = StringIO.new

    ENV.delete('choice')
    @repl.send(:__select_loop, 'choice', %w[apple banana cherry]) { }
    $stdout = old_stdout
    $stdin = old_stdin

    assert_equal 'banana', get_shell_var('choice')
  end

  def test_select_loop_sets_empty_for_invalid_selection
    old_stdin = $stdin
    $stdin = StringIO.new("99\n")

    old_stdout = $stdout
    $stdout = StringIO.new

    ENV['choice'] = 'initial'
    @repl.send(:__select_loop, 'choice', %w[a b c]) { }
    $stdout = old_stdout
    $stdin = old_stdin

    assert_equal '', get_shell_var('choice')
  end

  def test_select_loop_sets_empty_for_non_numeric
    old_stdin = $stdin
    $stdin = StringIO.new("invalid\n")

    old_stdout = $stdout
    $stdout = StringIO.new

    ENV['choice'] = 'initial'
    @repl.send(:__select_loop, 'choice', %w[a b c]) { }
    $stdout = old_stdout
    $stdin = old_stdin

    assert_equal '', get_shell_var('choice')
  end

  def test_select_loop_uses_ps3_prompt
    old_stdin = $stdin
    $stdin = StringIO.new("1\n")

    old_stdout = $stdout
    output = StringIO.new
    $stdout = output

    ENV['PS3'] = 'Choose: '
    @repl.send(:__select_loop, 'choice', %w[a]) { }
    $stdout = old_stdout
    $stdin = old_stdin

    assert_match(/Choose: /, output.string)
  end

  def test_select_loop_default_prompt
    old_stdin = $stdin
    $stdin = StringIO.new("1\n")

    old_stdout = $stdout
    output = StringIO.new
    $stdout = output

    ENV.delete('PS3')
    @repl.send(:__select_loop, 'choice', %w[a]) { }
    $stdout = old_stdout
    $stdin = old_stdin

    assert_match(/#\? /, output.string)
  end

  def test_select_loop_empty_items
    # Should return immediately for empty items
    old_stdin = $stdin
    $stdin = StringIO.new("1\n")

    old_stdout = $stdout
    $stdout = StringIO.new

    block_called = false
    @repl.send(:__select_loop, 'choice', []) { block_called = true }
    $stdout = old_stdout
    $stdin = old_stdin

    assert_false block_called
  end

  def test_select_loop_executes_block
    old_stdin = $stdin
    $stdin = StringIO.new("1\n")

    old_stdout = $stdout
    $stdout = StringIO.new

    block_called = false
    @repl.send(:__select_loop, 'choice', %w[a b]) { block_called = true }
    $stdout = old_stdout
    $stdin = old_stdin

    assert_true block_called
  end

  def test_select_loop_multiple_iterations
    old_stdin = $stdin
    # Select 1, then 2, then EOF
    $stdin = StringIO.new("1\n2\n")

    old_stdout = $stdout
    $stdout = StringIO.new

    selections = []
    @repl.send(:__select_loop, 'choice', %w[a b c]) { selections << get_shell_var('choice') }
    $stdout = old_stdout
    $stdin = old_stdin

    assert_equal %w[a b], selections
  end

  def test_select_first_item_is_index_1
    old_stdin = $stdin
    $stdin = StringIO.new("1\n")

    old_stdout = $stdout
    $stdout = StringIO.new

    @repl.send(:__select_loop, 'choice', %w[first second third]) { }
    $stdout = old_stdout
    $stdin = old_stdin

    assert_equal 'first', get_shell_var('choice')
  end

  def test_select_zero_is_invalid
    old_stdin = $stdin
    $stdin = StringIO.new("0\n")

    old_stdout = $stdout
    $stdout = StringIO.new

    ENV['choice'] = 'initial'
    @repl.send(:__select_loop, 'choice', %w[a b c]) { }
    $stdout = old_stdout
    $stdin = old_stdin

    assert_equal '', get_shell_var('choice')
  end
end
