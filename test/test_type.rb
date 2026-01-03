# frozen_string_literal: true

require_relative 'test_helper'

class TestType < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_type_test')
    Rubish::Builtins.clear_aliases
  end

  def teardown
    Rubish::Builtins.clear_aliases
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test type for builtins
  def test_type_builtin_cd
    output = capture_output { Rubish::Builtins.run('type', ['cd']) }
    assert_match(/cd is a shell builtin/, output)
  end

  def test_type_builtin_echo
    output = capture_output { Rubish::Builtins.run('type', ['echo']) }
    assert_match(/echo is a shell builtin/, output)
  end

  def test_type_builtin_export
    output = capture_output { Rubish::Builtins.run('type', ['export']) }
    assert_match(/export is a shell builtin/, output)
  end

  # Test type for aliases
  def test_type_alias
    Rubish::Builtins.run('alias', ['ll=ls -la'])
    output = capture_output { Rubish::Builtins.run('type', ['ll']) }
    assert_match(/ll is aliased to 'ls -la'/, output)
  end

  # Test type for functions
  def test_type_function
    execute('myfunc() { echo hello; }')
    output = capture_output { Rubish::Builtins.run('type', ['myfunc']) }
    assert_match(/myfunc is a function/, output)
  end

  # Test type for external commands
  def test_type_external_ls
    output = capture_output { Rubish::Builtins.run('type', ['ls']) }
    assert_match(%r{ls is /}, output)
  end

  def test_type_external_cat
    output = capture_output { Rubish::Builtins.run('type', ['cat']) }
    assert_match(%r{cat is /}, output)
  end

  # Test type not found
  def test_type_not_found
    output = capture_output { result = Rubish::Builtins.run('type', ['nonexistent_command_xyz']) }
    assert_match(/not found/, output)
  end

  # Test -t flag (type only)
  def test_type_t_flag_builtin
    output = capture_output { Rubish::Builtins.run('type', ['-t', 'cd']) }
    assert_equal "builtin\n", output
  end

  def test_type_t_flag_alias
    Rubish::Builtins.run('alias', ['ll=ls -la'])
    output = capture_output { Rubish::Builtins.run('type', ['-t', 'll']) }
    assert_equal "alias\n", output
  end

  def test_type_t_flag_function
    execute('myfunc() { echo hello; }')
    output = capture_output { Rubish::Builtins.run('type', ['-t', 'myfunc']) }
    assert_equal "function\n", output
  end

  def test_type_t_flag_file
    output = capture_output { Rubish::Builtins.run('type', ['-t', 'ls']) }
    assert_equal "file\n", output
  end

  def test_type_t_flag_not_found
    output = capture_output { Rubish::Builtins.run('type', ['-t', 'nonexistent_xyz']) }
    assert_equal '', output  # -t outputs nothing for not found
  end

  # Test -p flag (path only)
  def test_type_p_flag_external
    output = capture_output { Rubish::Builtins.run('type', ['-p', 'ls']) }
    assert_match(%r{^/.*ls$}, output.strip)
  end

  def test_type_p_flag_builtin
    output = capture_output { Rubish::Builtins.run('type', ['-p', 'cd']) }
    assert_equal '', output  # -p doesn't print builtins
  end

  # Test -P flag (force PATH search)
  def test_type_P_flag
    output = capture_output { Rubish::Builtins.run('type', ['-P', 'echo']) }
    # echo exists both as builtin and external; -P forces PATH search
    assert_match(%r{/.*echo}, output)
  end

  # Test -f flag (suppress functions)
  def test_type_f_flag
    execute('ls() { echo fake ls; }')
    output = capture_output { Rubish::Builtins.run('type', ['-f', 'ls']) }
    # Should find the external ls, not the function
    assert_match(%r{ls is /}, output)
  end

  # Test multiple names
  def test_type_multiple_names
    output = capture_output { Rubish::Builtins.run('type', ['cd', 'echo', 'ls']) }
    assert_match(/cd is a shell builtin/, output)
    assert_match(/echo is a shell builtin/, output)
    assert_match(%r{ls is /}, output)
  end

  # Test usage error
  def test_type_no_args
    output = capture_output { Rubish::Builtins.run('type', []) }
    assert_match(/usage/, output)
  end

  # Test via REPL
  def test_type_via_repl
    file = File.join(@tempdir, 'output.txt')
    execute("type cd > #{file}")
    assert_match(/cd is a shell builtin/, File.read(file))
  end

  # Test type returns false for not found
  def test_type_returns_false_for_not_found
    capture_output do
      result = Rubish::Builtins.run('type', ['nonexistent_command_xyz'])
      assert_false result
    end
  end

  # Test type returns true for found
  def test_type_returns_true_for_found
    capture_output do
      result = Rubish::Builtins.run('type', ['cd'])
      assert result
    end
  end

  # Test find_in_path helper
  def test_find_in_path_existing
    path = Rubish::Builtins.find_in_path('ls')
    assert_not_nil path
    assert File.executable?(path)
  end

  def test_find_in_path_nonexistent
    path = Rubish::Builtins.find_in_path('nonexistent_command_xyz')
    assert_nil path
  end
end
