# frozen_string_literal: true

require_relative 'test_helper'

class TestCoproc < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_coproc_test')
    # Clear any existing coprocs
    Rubish::Builtins.coprocs.keys.each { |name| Rubish::Builtins.remove_coproc(name) }
  end

  def teardown
    # Clean up any coprocs created during tests
    Rubish::Builtins.coprocs.keys.each { |name| Rubish::Builtins.remove_coproc(name) }
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test basic coproc syntax parsing
  def test_lexer_recognizes_coproc_keyword
    lexer = Rubish::Lexer.new('coproc cat')
    tokens = lexer.tokenize
    assert_equal :COPROC, tokens.first.type
  end

  def test_parser_creates_coproc_node_with_default_name
    tokens = Rubish::Lexer.new('coproc cat').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    assert_instance_of Rubish::AST::Coproc, ast
    assert_equal 'COPROC', ast.name
    assert_instance_of Rubish::AST::Command, ast.command
    assert_equal 'cat', ast.command.name
  end

  def test_parser_creates_coproc_node_with_custom_name
    tokens = Rubish::Lexer.new('coproc mycoproc cat').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    assert_instance_of Rubish::AST::Coproc, ast
    assert_equal 'mycoproc', ast.name
    assert_instance_of Rubish::AST::Command, ast.command
    assert_equal 'cat', ast.command.name
  end

  def test_parser_coproc_with_command_args
    tokens = Rubish::Lexer.new('coproc myproc cat -n').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    assert_instance_of Rubish::AST::Coproc, ast
    assert_equal 'myproc', ast.name
    assert_equal 'cat', ast.command.name
    assert_equal ['-n'], ast.command.args
  end

  # Test codegen
  def test_codegen_generates_coproc_call
    tokens = Rubish::Lexer.new('coproc cat').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    codegen = Rubish::Codegen.new
    code = codegen.generate(ast)
    assert_match(/__coproc\("COPROC"\)/, code)
  end

  def test_codegen_generates_coproc_call_with_name
    tokens = Rubish::Lexer.new('coproc myproc cat').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    codegen = Rubish::Codegen.new
    code = codegen.generate(ast)
    assert_match(/__coproc\("myproc"\)/, code)
  end

  # Test coproc execution
  def test_coproc_creates_background_process
    output = capture_output { execute('coproc cat') }
    assert_match(/\[coproc\] COPROC \d+/, output)

    # Check that coproc exists
    assert Rubish::Builtins.coproc?('COPROC')

    # Check PID is stored
    pid = Rubish::Builtins.coproc_pid('COPROC')
    assert pid.is_a?(Integer)
    assert pid > 0
  end

  def test_coproc_with_custom_name
    output = capture_output { execute('coproc mycat cat') }
    assert_match(/\[coproc\] mycat \d+/, output)

    assert Rubish::Builtins.coproc?('mycat')
    assert_false Rubish::Builtins.coproc?('COPROC')
  end

  def test_coproc_stores_file_descriptors_as_array
    execute('coproc cat')

    # File descriptors should be stored as array
    arr = Rubish::Builtins.get_array('COPROC')
    assert_equal 2, arr.length
    assert arr[0].to_i > 0  # read fd
    assert arr[1].to_i > 0  # write fd
  end

  def test_coproc_stores_pid_in_env
    execute('coproc myproc cat')

    pid_env = ENV['myproc_PID']
    assert_not_nil pid_env
    assert pid_env.to_i > 0
    assert_equal Rubish::Builtins.coproc_pid('myproc'), pid_env.to_i
  end

  def test_coproc_fails_if_name_exists
    execute('coproc myproc cat')
    stderr = capture_stderr { execute('coproc myproc cat') }
    assert_match(/already exists/, stderr)
  end

  def test_coproc_bidirectional_communication
    # Start a coproc that echoes back what it receives
    execute('coproc cat')

    # Get the reader and writer
    reader = Rubish::Builtins.coproc_reader('COPROC')
    writer = Rubish::Builtins.coproc_writer('COPROC')

    # Write to the coproc
    writer.puts 'hello world'
    writer.flush

    # Read back from the coproc
    result = reader.gets
    assert_equal "hello world\n", result
  end

  def test_remove_coproc
    execute('coproc myproc cat')
    assert Rubish::Builtins.coproc?('myproc')

    Rubish::Builtins.remove_coproc('myproc')
    assert_false Rubish::Builtins.coproc?('myproc')
    assert_nil ENV['myproc_PID']
    assert_equal [], Rubish::Builtins.get_array('myproc')
  end

  def test_coproc_with_compound_command
    # Test with a while loop
    tokens = Rubish::Lexer.new('coproc while true; do echo hello; done').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    assert_instance_of Rubish::AST::Coproc, ast
    assert_equal 'COPROC', ast.name
    assert_instance_of Rubish::AST::While, ast.command
  end
end
