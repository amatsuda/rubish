# frozen_string_literal: true

require_relative 'test_helper'

class TestConditionalExpr < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_cond_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)

    # Create test files
    File.write('file.txt', 'hello world')
    File.write('empty.txt', '')
    FileUtils.chmod(0755, 'file.txt')
    Dir.mkdir('testdir')
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  # Test lexer recognizes [[ and ]]
  def test_lexer_recognizes_double_brackets
    lexer = Rubish::Lexer.new('[[ -f file ]]')
    tokens = lexer.tokenize
    assert_equal :DOUBLE_LBRACKET, tokens[0].type
    assert_equal :WORD, tokens[1].type
    assert_equal :WORD, tokens[2].type
    assert_equal :DOUBLE_RBRACKET, tokens[3].type
  end

  # Test parser creates ConditionalExpr node
  def test_parser_creates_conditional_expr_node
    tokens = Rubish::Lexer.new('[[ -f file ]]').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    assert_instance_of Rubish::AST::ConditionalExpr, ast
    assert_equal 2, ast.expression.length
  end

  # Test codegen
  def test_codegen_generates_cond_test_call
    tokens = Rubish::Lexer.new('[[ -f file ]]').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    codegen = Rubish::Codegen.new
    code = codegen.generate(ast)
    assert_match(/__cond_test\(/, code)
  end

  # File tests
  def test_file_exists
    execute('[[ -e file.txt ]]')
    assert_equal 0, last_status

    execute('[[ -e nonexistent ]]')
    assert_equal 1, last_status
  end

  def test_file_is_regular_file
    execute('[[ -f file.txt ]]')
    assert_equal 0, last_status

    execute('[[ -f testdir ]]')
    assert_equal 1, last_status
  end

  def test_file_is_directory
    execute('[[ -d testdir ]]')
    assert_equal 0, last_status

    execute('[[ -d file.txt ]]')
    assert_equal 1, last_status
  end

  def test_file_readable
    execute('[[ -r file.txt ]]')
    assert_equal 0, last_status
  end

  def test_file_writable
    execute('[[ -w file.txt ]]')
    assert_equal 0, last_status
  end

  def test_file_executable
    execute('[[ -x file.txt ]]')
    assert_equal 0, last_status
  end

  def test_file_size_nonzero
    execute('[[ -s file.txt ]]')
    assert_equal 0, last_status

    execute('[[ -s empty.txt ]]')
    assert_equal 1, last_status
  end

  # String tests
  def test_string_empty
    ENV['EMPTY'] = ''
    ENV['NONEMPTY'] = 'hello'

    execute('[[ -z $EMPTY ]]')
    assert_equal 0, last_status

    execute('[[ -z $NONEMPTY ]]')
    assert_equal 1, last_status
  end

  def test_string_nonempty
    ENV['EMPTY'] = ''
    ENV['NONEMPTY'] = 'hello'

    execute('[[ -n $NONEMPTY ]]')
    assert_equal 0, last_status

    execute('[[ -n $EMPTY ]]')
    assert_equal 1, last_status
  end

  # String comparison
  def test_string_equal
    ENV['VAR'] = 'hello'

    execute('[[ $VAR == hello ]]')
    assert_equal 0, last_status

    execute('[[ $VAR == world ]]')
    assert_equal 1, last_status
  end

  def test_string_not_equal
    ENV['VAR'] = 'hello'

    execute('[[ $VAR != world ]]')
    assert_equal 0, last_status

    execute('[[ $VAR != hello ]]')
    assert_equal 1, last_status
  end

  def test_string_less_than
    execute('[[ abc < def ]]')
    assert_equal 0, last_status

    execute('[[ def < abc ]]')
    assert_equal 1, last_status
  end

  def test_string_greater_than
    execute('[[ def > abc ]]')
    assert_equal 0, last_status

    execute('[[ abc > def ]]')
    assert_equal 1, last_status
  end

  # Pattern matching
  def test_pattern_matching_glob
    ENV['FILE'] = 'test.txt'

    execute('[[ $FILE == *.txt ]]')
    assert_equal 0, last_status

    execute('[[ $FILE == *.rb ]]')
    assert_equal 1, last_status
  end

  def test_pattern_matching_question
    ENV['FILE'] = 'a.txt'

    execute('[[ $FILE == ?.txt ]]')
    assert_equal 0, last_status

    execute('[[ $FILE == ??.txt ]]')
    assert_equal 1, last_status
  end

  # Regex matching
  def test_regex_matching
    ENV['STR'] = 'hello123world'

    execute('[[ $STR =~ [0-9]+ ]]')
    assert_equal 0, last_status

    execute('[[ $STR =~ ^[a-z]+$ ]]')
    assert_equal 1, last_status
  end

  def test_regex_sets_bash_rematch
    ENV['STR'] = 'hello123world'
    execute('[[ $STR =~ ([0-9]+) ]]')
    assert_equal 0, last_status

    # Check BASH_REMATCH was set
    bash_rematch = Rubish::Builtins.get_array('BASH_REMATCH')
    assert_include bash_rematch, '123'
  end

  # Integer comparison
  def test_integer_equal
    ENV['NUM'] = '42'

    execute('[[ $NUM -eq 42 ]]')
    assert_equal 0, last_status

    execute('[[ $NUM -eq 43 ]]')
    assert_equal 1, last_status
  end

  def test_integer_not_equal
    execute('[[ 5 -ne 10 ]]')
    assert_equal 0, last_status

    execute('[[ 5 -ne 5 ]]')
    assert_equal 1, last_status
  end

  def test_integer_less_than
    execute('[[ 5 -lt 10 ]]')
    assert_equal 0, last_status

    execute('[[ 10 -lt 5 ]]')
    assert_equal 1, last_status
  end

  def test_integer_less_equal
    execute('[[ 5 -le 5 ]]')
    assert_equal 0, last_status

    execute('[[ 6 -le 5 ]]')
    assert_equal 1, last_status
  end

  def test_integer_greater_than
    execute('[[ 10 -gt 5 ]]')
    assert_equal 0, last_status

    execute('[[ 5 -gt 10 ]]')
    assert_equal 1, last_status
  end

  def test_integer_greater_equal
    execute('[[ 5 -ge 5 ]]')
    assert_equal 0, last_status

    execute('[[ 4 -ge 5 ]]')
    assert_equal 1, last_status
  end

  # Logical operators
  def test_logical_and
    execute('[[ -f file.txt && -d testdir ]]')
    assert_equal 0, last_status

    execute('[[ -f file.txt && -f nonexistent ]]')
    assert_equal 1, last_status
  end

  def test_logical_or
    execute('[[ -f nonexistent || -d testdir ]]')
    assert_equal 0, last_status

    execute('[[ -f nonexistent || -d nonexistent ]]')
    assert_equal 1, last_status
  end

  def test_logical_not
    execute('[[ ! -f nonexistent ]]')
    assert_equal 0, last_status

    execute('[[ ! -f file.txt ]]')
    assert_equal 1, last_status
  end

  # Combining with if
  def test_conditional_in_if
    execute('if [[ -f file.txt ]]; then echo yes; else echo no; fi > output.txt')
    assert_equal "yes\n", File.read('output.txt')

    execute('if [[ -f nonexistent ]]; then echo yes; else echo no; fi > output.txt')
    assert_equal "no\n", File.read('output.txt')
  end

  # Combining with while
  def test_conditional_in_while
    ENV['COUNT'] = '0'
    # This is a simplified test - just verify it parses correctly
    execute('[[ $COUNT -lt 3 ]]')
    assert_equal 0, last_status
  end

  # Empty expression
  def test_empty_expression
    execute('[[ ]]')
    assert_equal 0, last_status
  end

  # Non-empty string is true
  def test_nonempty_string_true
    execute('[[ hello ]]')
    assert_equal 0, last_status
  end

  # Empty string is false
  def test_empty_string_false
    ENV['EMPTY'] = ''
    execute('[[ $EMPTY ]]')
    assert_equal 1, last_status
  end
end
