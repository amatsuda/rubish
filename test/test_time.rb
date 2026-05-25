# frozen_string_literal: true

require_relative 'test_helper'

class TestTime < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_time_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test lexer recognizes time keyword
  def test_lexer_recognizes_time_keyword
    lexer = Rubish::Lexer.new('time ls')
    tokens = lexer.tokenize
    assert_equal :TIME, tokens.first.type
    assert_equal :WORD, tokens[1].type
    assert_equal 'ls', tokens[1].value
  end

  def test_lexer_recognizes_time_with_p_flag
    lexer = Rubish::Lexer.new('time -p ls')
    tokens = lexer.tokenize
    assert_equal :TIME, tokens[0].type
    assert_equal :WORD, tokens[1].type
    assert_equal '-p', tokens[1].value
    assert_equal :WORD, tokens[2].type
    assert_equal 'ls', tokens[2].value
  end

  # Test parser creates Time AST node
  def test_parser_creates_time_node
    tokens = Rubish::Lexer.new('time ls').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    assert_instance_of Rubish::AST::Time, ast
    assert_equal false, ast.posix_format
    assert_instance_of Rubish::AST::Command, ast.command
    assert_equal 'ls', ast.command.name
  end

  def test_parser_creates_time_node_with_p_flag
    tokens = Rubish::Lexer.new('time -p ls').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    assert_instance_of Rubish::AST::Time, ast
    assert_equal true, ast.posix_format
    assert_equal 'ls', ast.command.name
  end

  def test_parser_time_with_command_args
    tokens = Rubish::Lexer.new('time ls -la').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    assert_instance_of Rubish::AST::Time, ast
    assert_equal 'ls', ast.command.name
    assert_equal ['-la'], ast.command.args
  end

  def test_parser_time_with_pipeline
    tokens = Rubish::Lexer.new('time ls | wc -l').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    assert_instance_of Rubish::AST::Time, ast
    assert_instance_of Rubish::AST::Pipeline, ast.command
    assert_equal 2, ast.command.commands.length
  end

  # Test codegen
  def test_codegen_generates_time_call
    tokens = Rubish::Lexer.new('time ls').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    codegen = Rubish::Codegen.new
    code = codegen.generate(ast)
    assert_match(/__time\(false\)/, code)
    assert_match(/__cmd\("ls"\)/, code)
  end

  def test_codegen_generates_time_call_with_posix_flag
    tokens = Rubish::Lexer.new('time -p ls').tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse
    codegen = Rubish::Codegen.new
    code = codegen.generate(ast)
    assert_match(/__time\(true\)/, code)
  end

  # Test time execution
  def test_time_outputs_timing_info
    stderr = capture_stderr { execute('time true') }
    assert_match(/real/, stderr)
    assert_match(/user/, stderr)
    assert_match(/sys/, stderr)
  end

  def test_time_default_format
    stderr = capture_stderr { execute('time true') }
    # Default format: Xm0.XXXs
    assert_match(/real\t\d+m[\d.]+s/, stderr)
    assert_match(/user\t\d+m[\d.]+s/, stderr)
    assert_match(/sys\t\d+m[\d.]+s/, stderr)
  end

  def test_time_posix_format
    stderr = capture_stderr { execute('time -p true') }
    # POSIX format: seconds with decimal
    assert_match(/real [\d.]+/, stderr)
    assert_match(/user [\d.]+/, stderr)
    assert_match(/sys [\d.]+/, stderr)
  end

  def test_time_returns_command_exit_status
    result = capture_stderr { execute('time true') }
    # true should succeed
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_time_with_failing_command
    capture_stderr { execute('time false') }
    # false should fail - but time itself succeeds, it just reports the command's status
    # Actually the command's exit status propagates through
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_time_with_sleep
    stderr = capture_stderr { execute('time sleep 0.1') }
    # Real time should be at least 0.1 seconds
    assert_match(/real/, stderr)
    # Extract real time and verify it's reasonable
    if stderr =~ /real\t(\d+)m([\d.]+)s/
      minutes = $1.to_i
      seconds = $2.to_f
      total = minutes * 60 + seconds
      assert total >= 0.1, "Expected real time >= 0.1s, got #{total}s"
    elsif stderr =~ /real ([\d.]+)/
      # POSIX format
      total = $1.to_f
      assert total >= 0.1, "Expected real time >= 0.1s, got #{total}s"
    end
  end

  def test_time_with_pipeline
    stderr = capture_stderr { execute('time echo hello | cat') }
    assert_match(/real/, stderr)
    assert_match(/user/, stderr)
    assert_match(/sys/, stderr)
  end

  def test_time_command_output_still_works
    execute("time echo hello > #{output_file}")
    # The command should still produce output
    assert File.exist?(output_file)
    assert_equal "hello\n", File.read(output_file)
  end

  # TIMEFORMAT tests
  def test_timeformat_basic
    ENV['TIMEFORMAT'] = 'real=%R user=%U sys=%S'
    stderr = capture_stderr { execute('time true') }
    assert_match(/real=[\d.]+/, stderr)
    assert_match(/user=[\d.]+/, stderr)
    assert_match(/sys=[\d.]+/, stderr)
  end

  def test_timeformat_with_precision
    ENV['TIMEFORMAT'] = '%2R'
    stderr = capture_stderr { execute('time true') }
    # Should have exactly 2 decimal places
    assert_match(/^\d+\.\d{2}$/, stderr.strip)
  end

  def test_timeformat_with_zero_precision
    ENV['TIMEFORMAT'] = '%0R'
    stderr = capture_stderr { execute('time true') }
    # Should have no decimal places
    assert_match(/^\d+$/, stderr.strip)
  end

  def test_timeformat_with_long_format
    ENV['TIMEFORMAT'] = '%lR'
    stderr = capture_stderr { execute('time true') }
    # Should have minutes format: Xm0.XXXs
    assert_match(/\d+m[\d.]+s/, stderr)
  end

  def test_timeformat_with_precision_and_long_format
    ENV['TIMEFORMAT'] = '%2lR'
    stderr = capture_stderr { execute('time true') }
    # Should have minutes format with 2 decimal places
    assert_match(/\d+m\d+\.\d{2}s/, stderr)
  end

  def test_timeformat_percentage
    ENV['TIMEFORMAT'] = 'CPU: %P%%'
    stderr = capture_stderr { execute('time true') }
    assert_match(/CPU: [\d.]+%/, stderr)
  end

  def test_timeformat_literal_percent
    ENV['TIMEFORMAT'] = '100%%'
    stderr = capture_stderr { execute('time true') }
    assert_equal "100%\n", stderr
  end

  def test_timeformat_newline_escape
    ENV['TIMEFORMAT'] = 'real=%R\nuser=%U'
    stderr = capture_stderr { execute('time true') }
    lines = stderr.strip.split("\n")
    assert_equal 2, lines.length
    assert_match(/^real=/, lines[0])
    assert_match(/^user=/, lines[1])
  end

  def test_timeformat_tab_escape
    ENV['TIMEFORMAT'] = 'real\t%R'
    stderr = capture_stderr { execute('time true') }
    assert_match(/real\t[\d.]+/, stderr)
  end

  def test_timeformat_empty_suppresses_output
    ENV['TIMEFORMAT'] = ''
    stderr = capture_stderr { execute('time true') }
    assert_equal '', stderr
  end

  def test_timeformat_all_specifiers
    ENV['TIMEFORMAT'] = 'R=%R U=%U S=%S P=%P'
    stderr = capture_stderr { execute('time true') }
    assert_match(/R=[\d.]+/, stderr)
    assert_match(/U=[\d.]+/, stderr)
    assert_match(/S=[\d.]+/, stderr)
    assert_match(/P=[\d.]+/, stderr)
  end

  def test_timeformat_overrides_default
    ENV['TIMEFORMAT'] = 'CUSTOM: %R'
    stderr = capture_stderr { execute('time true') }
    assert_match(/^CUSTOM:/, stderr)
    assert_no_match(/real\t/, stderr)  # Default format should not appear
  end

  def test_timeformat_posix_flag_overrides_timeformat
    ENV['TIMEFORMAT'] = 'CUSTOM: %R'
    stderr = capture_stderr { execute('time -p true') }
    # -p flag should override TIMEFORMAT
    assert_match(/^real /, stderr)
    assert_no_match(/CUSTOM/, stderr)
  end
end
