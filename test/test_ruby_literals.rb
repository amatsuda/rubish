# frozen_string_literal: true

require_relative 'test_helper'

class TestRubyLiterals < Test::Unit::TestCase
  # Lexer tests
  def test_lexer_array
    tokens = Rubish::Lexer.new('echo [1, 2, 3]').tokenize
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :ARRAY, tokens[1].type
    assert_equal '[1, 2, 3]', tokens[1].value
  end

  def test_lexer_nested_array
    tokens = Rubish::Lexer.new('echo [[1, 2], [3, 4]]').tokenize
    assert_equal 2, tokens.length
    assert_equal :ARRAY, tokens[1].type
    assert_equal '[[1, 2], [3, 4]]', tokens[1].value
  end

  def test_lexer_regexp
    # Use pattern with metacharacters to ensure it's recognized as regexp
    tokens = Rubish::Lexer.new('grep /pat+ern/ file.txt').tokenize
    assert_equal 3, tokens.length
    assert_equal :REGEXP, tokens[1].type
    assert_equal '/pat+ern/', tokens[1].value
  end

  def test_lexer_regexp_with_flags
    tokens = Rubish::Lexer.new('grep /pat+ern/i file.txt').tokenize
    assert_equal 3, tokens.length
    assert_equal :REGEXP, tokens[1].type
    assert_equal '/pat+ern/i', tokens[1].value
  end

  def test_lexer_simple_pattern_is_path
    # Simple alphanumeric patterns without metacharacters are paths, not regexps
    # This allows /bin/ to work as a directory path
    tokens = Rubish::Lexer.new('ls /pattern/').tokenize
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/pattern/', tokens[1].value
  end

  def test_lexer_path_not_regexp
    tokens = Rubish::Lexer.new('cat /tmp/file').tokenize
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :WORD, tokens[1].type
    assert_equal '/tmp/file', tokens[1].value
  end

  def test_lexer_block_brace
    tokens = Rubish::Lexer.new('ls { |f| puts f }').tokenize
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :BLOCK, tokens[1].type
    assert_equal '{ |f| puts f }', tokens[1].value
  end

  def test_lexer_block_do_end
    tokens = Rubish::Lexer.new('ls do |f| puts f end').tokenize
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :BLOCK, tokens[1].type
    assert_equal 'do |f| puts f end', tokens[1].value
  end

  # Parser tests
  def test_parser_array_arg
    tokens = Rubish::Lexer.new('echo [1, 2, 3]').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'echo', ast.name
    assert_equal 1, ast.args.length
    assert_instance_of Rubish::AST::ArrayLiteral, ast.args[0]
  end

  def test_parser_regexp_arg
    tokens = Rubish::Lexer.new('grep /foo+/ file').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'grep', ast.name
    assert_equal 2, ast.args.length
    assert_instance_of Rubish::AST::RegexpLiteral, ast.args[0]
    assert_equal 'file', ast.args[1]
  end

  def test_parser_block
    tokens = Rubish::Lexer.new('ls { |f| puts f }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Command, ast
    assert_equal 'ls', ast.name
    assert_equal '{ |f| puts f }', ast.block
  end

  # Codegen tests
  def test_codegen_array
    tokens = Rubish::Lexer.new('echo [1, 2, 3]').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_equal '__cmd("echo", *[[1, 2, 3]].flatten)', code
  end

  def test_codegen_regexp
    tokens = Rubish::Lexer.new('grep /foo+/i file').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_equal '__cmd("grep", *[/foo+/i, "file"].flatten)', code
  end

  def test_codegen_block
    tokens = Rubish::Lexer.new('ls { |f| puts f }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_equal '__cmd("ls") { |f| puts f }', code
  end

  # Command execution tests
  def test_command_array_expansion
    output = capture_command_output do |f|
      cmd = Rubish::Command.new('echo', [1, 2, 3])
      cmd.redirect_out(f.path)
      cmd.run
    end
    assert_equal "1 2 3\n", output
  end

  def test_command_regexp_arg
    Tempfile.create('rubish_test') do |f|
      File.write(f.path, "hello world\nfoo bar\n")

      output = capture_command_output do |out|
        cmd = Rubish::Command.new('grep', /foo/)
        cmd.redirect_in(f.path)
        cmd.redirect_out(out.path)
        cmd.run
      end

      assert_equal "foo bar\n", output
    end
  end

  def test_command_with_block
    results = []
    cmd = Rubish::Command.new('printf', "a\nb\nc") do |line|
      results << line.upcase
    end
    cmd.run

    assert_equal %w[A B C], results
  end

  private

  def capture_command_output
    Tempfile.create('rubish_test') do |f|
      yield f
      return File.read(f.path)
    end
  end
end
