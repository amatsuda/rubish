# frozen_string_literal: true

require_relative 'test_helper'

class TestLastpipe < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_lastpipe_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
  end

  def test_lastpipe_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('lastpipe')
  end

  def test_lastpipe_can_be_enabled
    execute('shopt -s lastpipe')
    assert Rubish::Builtins.shopt_enabled?('lastpipe')
  end

  def test_lastpipe_can_be_disabled
    execute('shopt -s lastpipe')
    execute('shopt -u lastpipe')
    assert_false Rubish::Builtins.shopt_enabled?('lastpipe')
  end

  def test_without_lastpipe_read_variable_not_set
    # Without lastpipe, read runs in a subshell and variable is lost
    ENV['myvar'] = ''
    execute('echo hello | read myvar')
    # Variable should still be empty (read ran in subshell)
    assert_equal '', ENV['myvar'].to_s
  end

  def test_with_lastpipe_read_variable_is_set
    execute('shopt -s lastpipe')
    ENV['myvar'] = ''
    execute('echo hello | read myvar')
    # Variable should be set (read ran in current shell)
    assert_equal 'hello', ENV['myvar']
  end

  def test_lastpipe_with_multiple_pipes
    execute('shopt -s lastpipe')
    ENV['result'] = ''
    execute('echo "hello world" | tr " " "_" | read result')
    assert_equal 'hello_world', ENV['result']
  end

  def test_lastpipe_preserves_pipeline_output
    output_file = File.join(@tempdir, 'output.txt')
    execute('shopt -s lastpipe')
    execute("echo hello | cat > #{output_file}")
    assert File.exist?(output_file)
    assert_equal "hello\n", File.read(output_file)
  end

  def test_lastpipe_with_head
    execute('shopt -s lastpipe')
    ENV['firstline'] = ''
    # Test with a builtin reading first line
    File.write(File.join(@tempdir, 'lines.txt'), "line1\nline2\nline3\n")
    execute("cat #{File.join(@tempdir, 'lines.txt')} | read firstline")
    # With lastpipe, read gets the first line
    assert_equal 'line1', ENV['firstline']
  end

  def test_lastpipe_exit_status
    execute('shopt -s lastpipe')
    execute('echo test | true')
    assert_equal 0, @repl.instance_variable_get(:@last_status)

    execute('echo test | false')
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_lastpipe_pipestatus
    execute('shopt -s lastpipe')
    execute('true | false')
    pipestatus = @repl.instance_variable_get(:@pipestatus)
    assert_equal [0, 1], pipestatus
  end

  def test_single_command_not_affected
    # lastpipe only affects pipelines with multiple commands
    execute('shopt -s lastpipe')
    ENV['myvar'] = 'test'
    execute('echo hello')  # Single command, not a pipeline
    # Should work normally
    assert_equal 'test', ENV['myvar']
  end

  def test_lastpipe_with_external_command
    execute('shopt -s lastpipe')
    output_file = File.join(@tempdir, 'output.txt')
    # External command as last pipeline element
    execute("echo hello | cat > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end
end
