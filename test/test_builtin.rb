# frozen_string_literal: true

require_relative 'test_helper'

class TestBuiltin < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_builtin_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test builtin is itself a builtin
  def test_builtin_is_builtin
    assert Rubish::Builtins.builtin?('builtin')
  end

  # Test builtin runs builtins
  def test_builtin_runs_echo
    output = capture_output { Rubish::Builtins.run('builtin', ['echo', 'hello']) }
    assert_equal "hello\n", output
  end

  def test_builtin_runs_pwd
    output = capture_output { Rubish::Builtins.run('builtin', ['pwd']) }
    assert_match %r{/}, output
  end

  def test_builtin_runs_cd
    original_dir = Dir.pwd
    expected = File.realpath(@tempdir)
    Rubish::Builtins.run('builtin', ['cd', @tempdir])
    assert_equal expected, File.realpath(Dir.pwd)
    Dir.chdir(original_dir)
  end

  def test_builtin_runs_true
    result = Rubish::Builtins.run('builtin', ['true'])
    assert result
  end

  def test_builtin_runs_false
    result = Rubish::Builtins.run('builtin', ['false'])
    assert_false result
  end

  # Test builtin fails for non-builtins
  def test_builtin_fails_for_external
    output = capture_output { result = Rubish::Builtins.run('builtin', ['ls']) }
    assert_match(/not a shell builtin/, output)
  end

  def test_builtin_returns_false_for_external
    capture_output do
      result = Rubish::Builtins.run('builtin', ['ls'])
      assert_false result
    end
  end

  # Test builtin bypasses functions
  def test_builtin_bypasses_function
    execute('echo() { printf "fake"; }')
    output = capture_output { execute('builtin echo real') }
    assert_equal "real\n", output
  end

  # Test usage error
  def test_builtin_no_args
    output = capture_output { Rubish::Builtins.run('builtin', []) }
    assert_match(/usage/, output)
  end

  # Test type identifies builtin as builtin
  def test_type_identifies_builtin_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['builtin']) }
    assert_match(/builtin is a shell builtin/, output)
  end

  # Test via REPL
  def test_builtin_via_repl
    output = capture_output { execute('builtin echo hello world') }
    assert_equal "hello world\n", output
  end

  def test_builtin_cd_via_repl
    original_dir = Dir.pwd
    expected = File.realpath(@tempdir)
    execute("builtin cd #{@tempdir}")
    assert_equal expected, File.realpath(Dir.pwd)
    Dir.chdir(original_dir)
  end
end
