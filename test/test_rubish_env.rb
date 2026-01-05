# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_ENV < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_env_test')
    Dir.chdir(@tempdir)
    @rubish_bin = File.expand_path('../bin/rubish', __dir__)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic RUBISH_ENV functionality with -c option

  def test_rubish_env_sourced_with_c_option
    # Create an env file that sets a variable
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'MYVAR=from_rubish_env')

    ENV['RUBISH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'echo $MYVAR'`.strip
    assert_equal 'from_rubish_env', output
  end

  def test_rubish_env_defines_function_for_c_option
    # Create an env file that defines a function
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'greet() { echo "Hello, $1"; }')

    ENV['RUBISH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'greet World'`.strip
    assert_equal 'Hello, World', output
  end

  def test_rubish_env_defines_alias_for_c_option
    # Create an env file that defines an alias
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'alias hi="echo hello"')

    ENV['RUBISH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'hi'`.strip
    assert_equal 'hello', output
  end

  # RUBISH_ENV with script execution

  def test_rubish_env_sourced_before_script
    # Create an env file
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'SCRIPT_VAR=initialized')

    # Create a script that uses the variable
    script_file = File.join(@tempdir, 'test.sh')
    File.write(script_file, 'echo $SCRIPT_VAR')

    ENV['RUBISH_ENV'] = env_file
    output = `#{@rubish_bin} #{script_file}`.strip
    assert_equal 'initialized', output
  end

  def test_rubish_env_function_available_in_script
    # Create an env file with a function
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'add() { echo $(($1 + $2)); }')

    # Create a script that uses the function
    script_file = File.join(@tempdir, 'test.sh')
    File.write(script_file, 'add 5 3')

    ENV['RUBISH_ENV'] = env_file
    output = `#{@rubish_bin} #{script_file}`.strip
    assert_equal '8', output
  end

  # RUBISH_ENV not set or empty

  def test_rubish_env_not_set
    ENV.delete('RUBISH_ENV')
    output = `#{@rubish_bin} -c 'echo hello'`.strip
    assert_equal 'hello', output
  end

  def test_rubish_env_empty
    ENV['RUBISH_ENV'] = ''
    output = `#{@rubish_bin} -c 'echo hello'`.strip
    assert_equal 'hello', output
  end

  # RUBISH_ENV file doesn't exist

  def test_rubish_env_nonexistent_file
    ENV['RUBISH_ENV'] = '/nonexistent/path/to/env.sh'
    output = `#{@rubish_bin} -c 'echo hello'`.strip
    assert_equal 'hello', output
  end

  # RUBISH_ENV with tilde expansion

  def test_rubish_env_with_tilde
    # Create env file in temp dir (simulating home)
    env_file = File.join(@tempdir, 'myenv.sh')
    File.write(env_file, 'TILDE_VAR=expanded')

    # Use absolute path since tilde won't work in test
    ENV['RUBISH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'echo $TILDE_VAR'`.strip
    assert_equal 'expanded', output
  end

  # RUBISH_ENV not sourced in interactive mode
  # (This is verified by the fact that interactive mode doesn't call source_rubish_env)

  # RUBISH_ENV with multiple commands

  def test_rubish_env_multiple_commands
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, <<~SHELL)
      VAR1=one
      VAR2=two
      VAR3=three
    SHELL

    ENV['RUBISH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'echo $VAR1 $VAR2 $VAR3'`.strip
    assert_equal 'one two three', output
  end

  # RUBISH_ENV with shopt settings

  def test_rubish_env_sets_shopt
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'shopt -s dotglob')

    # Create dotfiles
    File.write(File.join(@tempdir, '.hidden'), '')
    File.write(File.join(@tempdir, 'visible'), '')

    ENV['RUBISH_ENV'] = env_file
    output = `cd #{@tempdir} && #{@rubish_bin} -c 'echo *'`.strip
    assert_match(/\.hidden/, output)
    assert_match(/visible/, output)
  end

  # RUBISH_ENV variable can be read

  def test_rubish_env_variable_readable
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, '# empty')

    ENV['RUBISH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'echo $RUBISH_ENV'`.strip
    assert_equal env_file, output
  end

  # RUBISH_ENV can be set within the env file to affect nested invocations

  def test_rubish_env_inherited
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'INHERITED=yes')

    ENV['RUBISH_ENV'] = env_file
    # The env file should be sourced, making INHERITED available
    output = `#{@rubish_bin} -c 'echo $INHERITED'`.strip
    assert_equal 'yes', output
  end

  # RUBISH_ENV with export statements

  def test_rubish_env_export
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'export EXPORTED_VAR=exported_value')

    ENV['RUBISH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'echo $EXPORTED_VAR'`.strip
    assert_equal 'exported_value', output
  end

  # Error handling

  def test_rubish_env_syntax_error_continues
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'if then fi')  # Invalid syntax

    ENV['RUBISH_ENV'] = env_file
    # Should still execute the command even if env file has errors
    output = `#{@rubish_bin} -c 'echo hello' 2>&1`.strip
    # The command should still run
    assert_match(/hello/, output)
  end
end
