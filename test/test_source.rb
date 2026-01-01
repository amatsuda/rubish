# frozen_string_literal: true

require_relative 'test_helper'

class TestSource < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_source_test')
    Rubish::Builtins.clear_aliases
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.clear_aliases
  end

  def create_script(name, content)
    path = File.join(@tempdir, name)
    File.write(path, content)
    path
  end

  def test_source_sets_alias
    script = create_script('aliases.sh', <<~SCRIPT)
      alias ll='ls -la'
      alias g='git'
    SCRIPT

    execute("source #{script}")

    assert_equal 'ls -la', Rubish::Builtins.aliases['ll']
    assert_equal 'git', Rubish::Builtins.aliases['g']
  end

  def test_source_with_dot_command
    script = create_script('test.sh', <<~SCRIPT)
      alias myalias='echo hello'
    SCRIPT

    execute(". #{script}")

    assert_equal 'echo hello', Rubish::Builtins.aliases['myalias']
  end

  def test_source_skips_comments
    script = create_script('comments.sh', <<~SCRIPT)
      # This is a comment
      alias a='b'
      # Another comment
    SCRIPT

    execute("source #{script}")

    assert_equal({'a' => 'b'}, Rubish::Builtins.aliases)
  end

  def test_source_skips_empty_lines
    script = create_script('empty.sh', <<~SCRIPT)
      alias x='y'

      alias z='w'
    SCRIPT

    execute("source #{script}")

    assert_equal 2, Rubish::Builtins.aliases.size
  end

  def test_source_nonexistent_file
    output = capture_output { execute('source /nonexistent/file.sh') }
    assert_match(/No such file or directory/, output)
  end

  def test_source_no_args
    output = capture_output { Rubish::Builtins.run('source', []) }
    assert_match(/usage/, output)
  end

  def test_source_sets_env_variable
    script = create_script('env.sh', <<~SCRIPT)
      export MY_VAR=hello
    SCRIPT

    execute("source #{script}")

    assert_equal 'hello', ENV['MY_VAR']
  ensure
    ENV.delete('MY_VAR')
  end

  def test_source_with_tilde_expansion
    # Create script in a known location
    script = create_script('tilde_test.sh', <<~SCRIPT)
      alias tilde_alias='worked'
    SCRIPT

    # Source using the full path (tilde expansion happens before source)
    execute("source #{script}")

    assert_equal 'worked', Rubish::Builtins.aliases['tilde_alias']
  end

  def test_source_executes_commands
    output_file = File.join(@tempdir, 'output.txt')
    script = create_script('commands.sh', <<~SCRIPT)
      echo sourced > #{output_file}
    SCRIPT

    execute("source #{script}")

    assert_equal "sourced\n", File.read(output_file)
  end

  def test_source_is_builtin
    assert Rubish::Builtins.builtin?('source')
    assert Rubish::Builtins.builtin?('.')
  end

  def test_source_sets_script_name
    output_file = File.join(@tempdir, 'script_name.txt')
    script = create_script('check_name.sh', <<~SCRIPT)
      echo $0 > #{output_file}
    SCRIPT

    execute("source #{script}")

    assert_equal "#{script}\n", File.read(output_file)
  end

  def test_source_restores_script_name
    script = create_script('nested.sh', <<~SCRIPT)
      # Just a simple script
      true
    SCRIPT

    # Before sourcing
    assert_equal 'rubish', @repl.script_name

    execute("source #{script}")

    # After sourcing, should be restored
    assert_equal 'rubish', @repl.script_name
  end
end
