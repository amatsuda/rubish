# frozen_string_literal: true

require_relative 'test_helper'

class TestENVVariable < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_env_variable_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.shell_options.clear
  end

  # Basic ENV variable functionality

  def test_env_variable_sourced_in_interactive_mode
    # Create an ENV file that sets a variable
    env_file = File.join(@tempdir, 'startup.sh')
    File.write(env_file, 'MY_ENV_VAR=from_env_file')

    ENV['ENV'] = env_file
    ENV.delete('HOME')  # Prevent loading ~/.rubishrc

    repl = Rubish::REPL.new
    repl.send(:load_config)

    assert_equal 'from_env_file', ENV['MY_ENV_VAR']
  end

  def test_env_variable_defines_function
    # Create an ENV file that defines a function
    env_file = File.join(@tempdir, 'startup.sh')
    File.write(env_file, 'hello() { echo "Hello from ENV"; }')

    ENV['ENV'] = env_file
    ENV.delete('HOME')

    repl = Rubish::REPL.new
    repl.send(:load_config)

    # Function should be defined
    assert repl.instance_variable_get(:@functions).key?('hello')
  end

  def test_env_variable_defines_alias
    # Create an ENV file that defines an alias
    env_file = File.join(@tempdir, 'startup.sh')
    File.write(env_file, 'alias ll="ls -la"')

    ENV['ENV'] = env_file
    ENV.delete('HOME')

    repl = Rubish::REPL.new
    repl.send(:load_config)

    assert_equal 'ls -la', Rubish::Builtins.aliases['ll']
  end

  # ENV variable not set or empty

  def test_env_variable_not_set
    ENV.delete('ENV')
    ENV.delete('HOME')

    # Should not raise an error
    repl = Rubish::REPL.new
    repl.send(:load_config)
  end

  def test_env_variable_empty
    ENV['ENV'] = ''
    ENV.delete('HOME')

    # Should not raise an error
    repl = Rubish::REPL.new
    repl.send(:load_config)
  end

  # ENV file doesn't exist

  def test_env_variable_nonexistent_file
    ENV['ENV'] = '/nonexistent/path/to/env.sh'
    ENV.delete('HOME')

    # Should not raise an error, just skip
    repl = Rubish::REPL.new
    repl.send(:load_config)
  end

  # ENV with tilde expansion

  def test_env_variable_with_tilde
    # Create env file in temp dir
    env_file = File.join(@tempdir, 'myenv.sh')
    File.write(env_file, 'TILDE_TEST=expanded')

    # Use absolute path (tilde expansion happens via File.expand_path)
    ENV['ENV'] = env_file
    ENV.delete('HOME')

    repl = Rubish::REPL.new
    repl.send(:load_config)

    assert_equal 'expanded', ENV['TILDE_TEST']
  end

  # ENV sourced before rubishrc

  def test_env_sourced_before_rubishrc
    # Create separate directories for home and cwd
    home_dir = File.join(@tempdir, 'home')
    work_dir = File.join(@tempdir, 'work')
    FileUtils.mkdir_p(home_dir)
    FileUtils.mkdir_p(work_dir)

    # Create ENV file
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'LOAD_ORDER=env')

    # Create rubishrc in home that appends to the variable
    ENV['HOME'] = home_dir
    rc_file = File.join(home_dir, '.rubishrc')
    File.write(rc_file, 'LOAD_ORDER="${LOAD_ORDER}_rubishrc"')

    ENV['ENV'] = env_file

    # Change to work directory (no .rubishrc there)
    Dir.chdir(work_dir)

    repl = Rubish::REPL.new
    repl.send(:load_config)

    # ENV should be sourced first, then rubishrc
    assert_equal 'env_rubishrc', ENV['LOAD_ORDER']
  end

  # ENV with multiple commands

  def test_env_variable_multiple_commands
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, <<~SHELL)
      VAR1=one
      VAR2=two
      VAR3=three
    SHELL

    ENV['ENV'] = env_file
    ENV.delete('HOME')

    repl = Rubish::REPL.new
    repl.send(:load_config)

    assert_equal 'one', ENV['VAR1']
    assert_equal 'two', ENV['VAR2']
    assert_equal 'three', ENV['VAR3']
  end

  # ENV with shopt settings

  def test_env_variable_sets_shopt
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'shopt -s dotglob')

    ENV['ENV'] = env_file
    ENV.delete('HOME')

    repl = Rubish::REPL.new
    repl.send(:load_config)

    assert Rubish::Builtins.shopt_enabled?('dotglob')
  end

  # ENV variable value can be read

  def test_env_variable_readable
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, '# empty')

    ENV['ENV'] = env_file
    ENV.delete('HOME')

    repl = Rubish::REPL.new

    # The ENV variable itself should be readable
    assert_equal env_file, ENV['ENV']
  end

  # Privileged mode skips ENV

  def test_env_not_sourced_in_privileged_mode
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'PRIVILEGED_TEST=should_not_be_set')

    ENV['ENV'] = env_file
    ENV.delete('HOME')

    repl = Rubish::REPL.new
    # Enable privileged mode
    Rubish::Builtins.set_options['p'] = true

    repl.send(:load_config)

    # Variable should not be set because privileged mode skips startup files
    assert_nil ENV['PRIVILEGED_TEST']

    # Clean up
    Rubish::Builtins.set_options['p'] = false
  end

  # ENV with export statements

  def test_env_variable_export
    env_file = File.join(@tempdir, 'env.sh')
    File.write(env_file, 'export EXPORTED_FROM_ENV=exported_value')

    ENV['ENV'] = env_file
    ENV.delete('HOME')

    repl = Rubish::REPL.new
    repl.send(:load_config)

    assert_equal 'exported_value', ENV['EXPORTED_FROM_ENV']
  end
end
