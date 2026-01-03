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
end
