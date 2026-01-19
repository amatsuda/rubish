# frozen_string_literal: true

require_relative 'test_helper'

class TestEach < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_each_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_each_block_token
    tokens = Rubish::Lexer.new('ls.each {|x| echo $x }').tokenize
    # Should have WORD(ls), DOT, WORD(each), BLOCK
    assert_equal :WORD, tokens[0].type
    assert_equal 'ls', tokens[0].value
    assert_equal :DOT, tokens[1].type
    assert_equal :WORD, tokens[2].type
    assert_equal 'each', tokens[2].value
    assert_equal :BLOCK, tokens[3].type
    assert_match(/\|x\|.*echo/, tokens[3].value)
  end

  # Parser tests - each is parsed as a command in a pipeline
  def test_each_simple_parsing
    tokens = Rubish::Lexer.new('ls.each {|x| echo $x }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 2, ast.commands.length
    assert_equal 'ls', ast.commands[0].name
    assert_equal 'each', ast.commands[1].name
    assert_match(/\|x\|/, ast.commands[1].block)
  end

  def test_each_with_pipeline_parsing
    tokens = Rubish::Lexer.new('ls.grep(/foo/).each {|line| echo $line }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 3, ast.commands.length
    assert_equal 'each', ast.commands[2].name
  end

  # Codegen tests
  def test_each_codegen
    tokens = Rubish::Lexer.new('ls.each {|x| echo $x }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__each_loop/, code)
    assert_match(/__eval_shell_code/, code)
  end

  # Execution tests
  def test_each_iterates_over_lines
    # Test using printf as source (more portable than echo -e)
    execute("printf 'alpha\\nbeta\\ngamma\\n'.each {|x| echo \"got: $x\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/got: alpha/, content)
    assert_match(/got: beta/, content)
    assert_match(/got: gamma/, content)
  end

  def test_each_with_seq
    # Test using seq as source
    execute("seq(1, 3).each {|n| echo \"num: $n\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/num: 1/, content)
    assert_match(/num: 2/, content)
    assert_match(/num: 3/, content)
  end

  def test_each_with_ls
    # Create some test files
    File.write("#{@tempdir}/file1.txt", 'content1')
    File.write("#{@tempdir}/file2.txt", 'content2')

    # Use ls.each to iterate over files
    execute("ls(#{@tempdir}).each {|f| echo \"file: $f\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/file: file1\.txt/, content)
    assert_match(/file: file2\.txt/, content)
  end

  def test_each_with_pipeline_source
    # Create test file
    File.write("#{@tempdir}/data.txt", "foo\nbar\nfoo2\nbaz\n")

    # Use cat.grep as source (use string pattern, not regex literal for grep)
    execute("cat(#{@tempdir}/data.txt).grep(foo).each {|line| echo \"match: $line\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/match: foo/, content)
    assert_match(/match: foo2/, content)
    refute_match(/match: bar/, content)
    refute_match(/match: baz/, content)
  end

  # ==========================================================================
  # do...end block syntax tests
  # ==========================================================================

  def test_each_do_end_parsing
    tokens = Rubish::Lexer.new('ls | each do |x| echo $x end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 2, ast.commands.length
    assert_equal 'ls', ast.commands[0].name
    assert_equal 'each', ast.commands[1].name
    assert_match(/do.*\|x\|.*end/m, ast.commands[1].block)
  end

  def test_each_do_end_codegen
    tokens = Rubish::Lexer.new('ls | each do |x| echo $x end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__each_loop/, code)
    assert_match(/"x"/, code)  # variable name extracted
  end

  def test_each_do_end_execution
    execute("seq 1 3 | each do |n| echo \"num: $n\" >> #{output_file} end")
    content = File.read(output_file)
    assert_match(/num: 1/, content)
    assert_match(/num: 2/, content)
    assert_match(/num: 3/, content)
  end

  def test_each_do_end_with_pipeline
    File.write("#{@tempdir}/data.txt", "apple\nbanana\napricot\ncherry\n")
    execute("cat #{@tempdir}/data.txt | grep ap | each do |fruit| echo \"found: $fruit\" >> #{output_file} end")
    content = File.read(output_file)
    assert_match(/found: apple/, content)
    assert_match(/found: apricot/, content)
    refute_match(/found: banana/, content)
  end

  # ==========================================================================
  # Implicit $it variable tests
  # ==========================================================================

  def test_each_implicit_it_curly_brace
    execute("seq 1 3 | each { echo \"val: $it\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/val: 1/, content)
    assert_match(/val: 2/, content)
    assert_match(/val: 3/, content)
  end

  def test_each_implicit_it_do_end
    execute("seq 1 3 | each do echo \"val: $it\" >> #{output_file} end")
    content = File.read(output_file)
    assert_match(/val: 1/, content)
    assert_match(/val: 2/, content)
    assert_match(/val: 3/, content)
  end

  def test_each_implicit_it_method_chain
    execute("seq(1, 3).each { echo \"val: $it\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/val: 1/, content)
    assert_match(/val: 2/, content)
    assert_match(/val: 3/, content)
  end

  def test_each_implicit_it_lexer
    # Verify lexer produces BLOCK token for { body } after each
    tokens = Rubish::Lexer.new('ls | each { echo $it }').tokenize
    assert_equal :BLOCK, tokens.last.type
    assert_equal '{ echo $it }', tokens.last.value
  end

  def test_each_implicit_it_do_end_lexer
    # Verify lexer produces BLOCK token for do body end after each
    tokens = Rubish::Lexer.new('ls | each do echo $it end').tokenize
    assert_equal :BLOCK, tokens.last.type
    assert_match(/do.*end/, tokens.last.value)
  end
end
