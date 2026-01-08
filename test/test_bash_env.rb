# frozen_string_literal: true

require_relative 'test_helper'

class TestBASH_ENV < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('bash_env_test')
    Dir.chdir(@tempdir)
    @rubish_bin = File.expand_path('../bin/rubish', __dir__)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # BASH_ENV as fallback when RUBISH_ENV not set

  def test_bash_env_sourced_when_rubish_env_not_set
    # Create an env file that sets a variable
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'MYVAR=from_bash_env')

    ENV.delete('RUBISH_ENV')
    ENV['BASH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'echo $MYVAR'`.strip
    assert_equal 'from_bash_env', output
  end

  def test_bash_env_defines_function
    # Create an env file that defines a function
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'greet() { echo "Hi, $1"; }')

    ENV.delete('RUBISH_ENV')
    ENV['BASH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'greet World'`.strip
    assert_equal 'Hi, World', output
  end

  def test_bash_env_defines_alias
    # Create an env file that defines an alias
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'alias hey="echo hello"')

    ENV.delete('RUBISH_ENV')
    ENV['BASH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'hey'`.strip
    assert_equal 'hello', output
  end

  # RUBISH_ENV takes precedence over BASH_ENV

  def test_rubish_env_takes_precedence_over_bash_env
    # Create two different env files
    rubish_env_file = File.join(@tempdir, 'rubish_env.sh')
    bash_env_file = File.join(@tempdir, 'bash_env.sh')
    File.write(rubish_env_file, 'SOURCE=rubish')
    File.write(bash_env_file, 'SOURCE=bash')

    ENV['RUBISH_ENV'] = rubish_env_file
    ENV['BASH_ENV'] = bash_env_file
    output = `#{@rubish_bin} -c 'echo $SOURCE'`.strip
    assert_equal 'rubish', output, 'RUBISH_ENV should take precedence over BASH_ENV'
  end

  # BASH_ENV with script execution

  def test_bash_env_sourced_before_script
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'SCRIPT_VAR=from_bash_env')

    script_file = File.join(@tempdir, 'test.sh')
    File.write(script_file, 'echo $SCRIPT_VAR')

    ENV.delete('RUBISH_ENV')
    ENV['BASH_ENV'] = env_file
    output = `#{@rubish_bin} #{script_file}`.strip
    assert_equal 'from_bash_env', output
  end

  # BASH_ENV not set or empty

  def test_bash_env_not_set
    ENV.delete('RUBISH_ENV')
    ENV.delete('BASH_ENV')
    output = `#{@rubish_bin} -c 'echo hello'`.strip
    assert_equal 'hello', output
  end

  def test_bash_env_empty
    ENV.delete('RUBISH_ENV')
    ENV['BASH_ENV'] = ''
    output = `#{@rubish_bin} -c 'echo hello'`.strip
    assert_equal 'hello', output
  end

  # BASH_ENV file doesn't exist

  def test_bash_env_nonexistent_file
    ENV.delete('RUBISH_ENV')
    ENV['BASH_ENV'] = '/nonexistent/path/to/env.sh'
    output = `#{@rubish_bin} -c 'echo hello'`.strip
    assert_equal 'hello', output
  end

  # BASH_ENV variable is readable

  def test_bash_env_variable_readable
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, '# empty')

    ENV.delete('RUBISH_ENV')
    ENV['BASH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'echo $BASH_ENV'`.strip
    assert_equal env_file, output
  end

  # BASH_ENV with multiple commands

  def test_bash_env_multiple_commands
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, <<~SHELL)
      A=1
      B=2
      C=3
    SHELL

    ENV.delete('RUBISH_ENV')
    ENV['BASH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'echo $A $B $C'`.strip
    assert_equal '1 2 3', output
  end

  # BASH_ENV with shopt settings

  def test_bash_env_sets_shopt
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'shopt -s dotglob')

    # Create dotfiles
    File.write(File.join(@tempdir, '.hidden'), '')
    File.write(File.join(@tempdir, 'visible'), '')

    ENV.delete('RUBISH_ENV')
    ENV['BASH_ENV'] = env_file
    output = `cd #{@tempdir} && #{@rubish_bin} -c 'echo *'`.strip
    assert_match(/\.hidden/, output)
    assert_match(/visible/, output)
  end

  # BASH_ENV with export statements

  def test_bash_env_export
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'export EXPORTED=yes')

    ENV.delete('RUBISH_ENV')
    ENV['BASH_ENV'] = env_file
    output = `#{@rubish_bin} -c 'echo $EXPORTED'`.strip
    assert_equal 'yes', output
  end
end
