# frozen_string_literal: true

require_relative 'test_helper'

class TestCommand < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_command_test')
    Rubish::Builtins.clear_aliases
  end

  def teardown
    Rubish::Builtins.clear_aliases
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test command is a builtin
  def test_command_is_builtin
    assert Rubish::Builtins.builtin?('command')
  end

  # Test command -v for builtins
  def test_command_v_builtin
    output = capture_output { Rubish::Builtins.run('command', ['-v', 'cd']) }
    assert_equal "cd\n", output
  end

  def test_command_v_external
    output = capture_output { Rubish::Builtins.run('command', ['-v', 'ls']) }
    assert_match %r{/.*ls}, output
  end

  def test_command_v_not_found
    result = Rubish::Builtins.run('command', ['-v', 'nonexistent_xyz'])
    assert_false result
  end

  # Test command -V for descriptions
  def test_command_V_builtin
    output = capture_output { Rubish::Builtins.run('command', ['-V', 'cd']) }
    assert_match(/cd is a shell builtin/, output)
  end

  def test_command_V_external
    output = capture_output { Rubish::Builtins.run('command', ['-V', 'ls']) }
    assert_match(%r{ls is /}, output)
  end

  def test_command_V_not_found
    output = capture_output { Rubish::Builtins.run('command', ['-V', 'nonexistent_xyz']) }
    assert_match(/not found/, output)
  end

  # Test command bypasses aliases
  def test_command_bypasses_alias
    Rubish::Builtins.run('alias', ['ls=echo fake'])
    # command ls should run real ls, not the alias
    output = capture_output { execute('command ls') }
    # Real ls output won't contain 'fake'
    assert_no_match(/fake/, output)
  end

  # Test command bypasses functions
  def test_command_bypasses_function
    execute('echo() { printf "fake echo"; }')
    output = capture_output { execute('command echo hello') }
    # Should use real echo, not the function
    assert_equal "hello\n", output
  end

  # Test command runs external commands
  def test_command_runs_external
    output = capture_output { execute('command pwd') }
    assert_match %r{/}, output
  end

  # Test command runs builtins
  def test_command_runs_builtin_cd
    original_dir = Dir.pwd
    expected = File.realpath(@tempdir)
    execute("command cd #{@tempdir}")
    assert_equal expected, File.realpath(Dir.pwd)
    Dir.chdir(original_dir)
  end

  # Test usage error
  def test_command_no_args
    output = capture_output { Rubish::Builtins.run('command', []) }
    assert_match(/usage/, output)
  end

  def test_command_only_flags
    output = capture_output { Rubish::Builtins.run('command', ['-v']) }
    assert_match(/usage/, output)
  end

  # Test type identifies command as builtin
  def test_type_identifies_command_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['command']) }
    assert_match(/command is a shell builtin/, output)
  end

  # Test invalid option
  def test_command_invalid_option
    output = capture_output { Rubish::Builtins.run('command', ['-x', 'ls']) }
    assert_match(/invalid option/, output)
  end

  # Test executing a directory gives proper error
  def test_execute_directory_error
    error_file = File.join(@tempdir, 'stderr.txt')
    execute("#{@tempdir} 2>#{error_file}")
    assert_match(/Is a directory/, File.read(error_file))
    assert_equal 126, @repl.instance_variable_get(:@last_status)
  end

  # Test command not found gives proper error
  def test_command_not_found
    error_file = File.join(@tempdir, 'stderr.txt')
    execute("nonexistent_command_xyz 2>#{error_file}")
    assert_match(/command not found/, File.read(error_file))
    assert_equal 127, @repl.instance_variable_get(:@last_status)
  end
end
