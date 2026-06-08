# frozen_string_literal: true

require_relative 'test_helper'

class TestEval < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_eval_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test eval is a builtin
  def test_eval_is_builtin
    assert Rubish::Builtins.builtin?('eval')
  end

  # Test eval with no args returns true
  def test_eval_no_args_returns_true
    result = Rubish::Builtins.run('eval', [])
    assert result
  end

  # Test eval with export
  def test_eval_with_export
    execute('eval export EVAL_VAR=worked')
    assert_equal 'worked', ENV['EVAL_VAR']
  end

  # Test eval runs cd
  def test_eval_runs_cd
    original_dir = Dir.pwd
    expected = File.realpath(@tempdir)
    execute("eval cd #{@tempdir}")
    assert_equal expected, File.realpath(Dir.pwd)
    Dir.chdir(original_dir)
  end

  # Test eval runs echo builtin
  def test_eval_runs_echo_builtin
    output = capture_output { execute('eval echo hello') }
    assert_equal "hello\n", output
  end

  # Test eval with pwd
  def test_eval_runs_pwd
    output = capture_output { execute('eval pwd') }
    assert_match %r{/}, output
  end

  # Test type identifies eval as builtin
  def test_type_identifies_eval_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['eval']) }
    assert_match(/eval is a shell builtin/, output)
  end

  # Test eval with dynamic command via variable
  def test_eval_dynamic_command
    ENV['CMD'] = 'pwd'
    output = capture_output { execute('eval $CMD') }
    assert_match %r{/}, output
  end

  # Test nested eval
  def test_eval_nested
    ENV['NESTED_VAR'] = 'nested_value'
    execute('eval eval export RESULT=$NESTED_VAR')
    assert_equal 'nested_value', ENV['RESULT']
  end

  # eval'd content goes through the same line-by-line accumulator as source,
  # so multi-line input with comments, control structures, and function
  # definitions parses correctly — `eval "$(starship init zsh)"` and
  # similar plugin-style snippets need this.
  def test_eval_multi_line_with_leading_comment
    execute(%(eval "# a comment\nEVAL_MULTI_LEAD='val'\n"))
    assert_equal 'val', Rubish::Builtins.get_var('EVAL_MULTI_LEAD')
  ensure
    Rubish::Builtins.delete_var('EVAL_MULTI_LEAD')
  end

  def test_eval_multi_line_with_leading_blank_line
    execute(%(eval "\nEVAL_MULTI_BLANK='val'\n"))
    assert_equal 'val', Rubish::Builtins.get_var('EVAL_MULTI_BLANK')
  ensure
    Rubish::Builtins.delete_var('EVAL_MULTI_BLANK')
  end

  # If-block whose body uses `(( … ))`. Without the source-style line
  # tracker, the depth count never decrements and the rest of the eval
  # gets dropped. Use `$'…'` so the embedded `\n`s are real newlines
  # (matching bash, where `\n` inside `"…"` is literal).
  def test_eval_with_if_block_containing_arithmetic_command
    execute(%q{eval $'if true; then\n  (( EVAL_ARITH = 2 + 3 ))\nfi\nEVAL_AFTER_IF=reached\n'})
    assert_equal '5', Rubish::Builtins.get_var('EVAL_ARITH').to_s
    assert_equal 'reached', Rubish::Builtins.get_var('EVAL_AFTER_IF')
  ensure
    Rubish::Builtins.delete_var('EVAL_ARITH')
    Rubish::Builtins.delete_var('EVAL_AFTER_IF')
  end

  # Function definition inside eval: the body shouldn't run at eval time,
  # and a later call exercises it.
  def test_eval_function_definition_then_call
    execute(%(eval "evalf() { echo \\"got-\\$1\\"; }"))
    output = capture_output { execute('evalf hello') }
    assert_equal "got-hello\n", output
  end
end
