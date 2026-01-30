# frozen_string_literal: true

require_relative 'test_helper'

class TestSourcepath < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @original_dir = Dir.pwd
    @original_path = ENV['PATH']
    @tempdir = Dir.mktmpdir('rubish_sourcepath_test')
    @path_dir = File.join(@tempdir, 'bin')
    Dir.mkdir(@path_dir)
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV['PATH'] = @original_path
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
  end

  # sourcepath is enabled by default (like bash)
  def test_sourcepath_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('sourcepath')
  end

  def test_sourcepath_can_be_disabled
    execute('shopt -u sourcepath')
    assert_false Rubish::Builtins.shopt_enabled?('sourcepath')
  end

  def test_sourcepath_can_be_re_enabled
    execute('shopt -u sourcepath')
    execute('shopt -s sourcepath')
    assert Rubish::Builtins.shopt_enabled?('sourcepath')
  end

  def test_source_without_sourcepath_fails_for_path_file
    # Disable sourcepath
    execute('shopt -u sourcepath')

    # Create a script in PATH directory
    script_path = File.join(@path_dir, 'myscript.sh')
    File.write(script_path, "export SOURCED_VAR=from_path\n")

    # Add to PATH
    ENV['PATH'] = "#{@path_dir}:#{@original_path}"
    ENV['SOURCED_VAR'] = ''

    # Without sourcepath, should fail for file not in current directory
    output = capture_output do
      execute('source myscript.sh')
    end
    assert_match(/No such file or directory/, output)
    assert_equal '', ENV['SOURCED_VAR']
  end

  def test_source_with_sourcepath_finds_file_in_path
    # sourcepath is on by default
    # Create a script in PATH directory
    script_path = File.join(@path_dir, 'myscript.sh')
    File.write(script_path, "export SOURCED_VAR=from_path\n")

    # Add to PATH
    ENV['PATH'] = "#{@path_dir}:#{@original_path}"
    ENV['SOURCED_VAR'] = ''

    # With sourcepath (default), should find the file in PATH
    execute('source myscript.sh')
    assert_equal 'from_path', ENV['SOURCED_VAR']
  end

  def test_source_current_dir_takes_precedence
    # Create scripts in both current dir and PATH
    File.write(File.join(@tempdir, 'script.sh'), "export SOURCED_FROM=current\n")
    File.write(File.join(@path_dir, 'script.sh'), "export SOURCED_FROM=path\n")

    ENV['PATH'] = "#{@path_dir}:#{@original_path}"
    ENV['SOURCED_FROM'] = ''

    # Current directory should take precedence
    execute('source script.sh')
    assert_equal 'current', ENV['SOURCED_FROM']
  end

  def test_source_with_relative_path_ignores_sourcepath
    # Create a script in PATH directory only
    script_path = File.join(@path_dir, 'script.sh')
    File.write(script_path, "export SOURCED_VAR=found\n")

    ENV['PATH'] = "#{@path_dir}:#{@original_path}"
    ENV['SOURCED_VAR'] = ''

    # Using relative path with slash should not search PATH
    output = capture_output do
      execute('source ./nonexistent.sh')
    end
    assert_match(/No such file or directory/, output)
  end

  def test_source_absolute_path_works
    # Create a script
    script_path = File.join(@tempdir, 'script.sh')
    File.write(script_path, "export SOURCED_VAR=absolute\n")

    ENV['SOURCED_VAR'] = ''

    # Absolute path should work directly
    execute("source #{script_path}")
    assert_equal 'absolute', ENV['SOURCED_VAR']
  end

  def test_source_dot_builtin_also_uses_sourcepath
    # Create a script in PATH directory
    script_path = File.join(@path_dir, 'dotscript.sh')
    File.write(script_path, "export DOT_VAR=found\n")

    ENV['PATH'] = "#{@path_dir}:#{@original_path}"
    ENV['DOT_VAR'] = ''

    # The . builtin should also use sourcepath
    execute('. dotscript.sh')
    assert_equal 'found', ENV['DOT_VAR']
  end

  def test_sourcepath_searches_path_in_order
    # Create multiple PATH directories
    path_dir1 = File.join(@tempdir, 'bin1')
    path_dir2 = File.join(@tempdir, 'bin2')
    Dir.mkdir(path_dir1)
    Dir.mkdir(path_dir2)

    File.write(File.join(path_dir1, 'order.sh'), "export ORDER_VAR=first\n")
    File.write(File.join(path_dir2, 'order.sh'), "export ORDER_VAR=second\n")

    ENV['PATH'] = "#{path_dir1}:#{path_dir2}:#{@original_path}"
    ENV['ORDER_VAR'] = ''

    # Should find the first one in PATH order
    execute('source order.sh')
    assert_equal 'first', ENV['ORDER_VAR']
  end

  def test_sourcepath_not_found_in_path
    ENV['PATH'] = "#{@path_dir}:#{@original_path}"

    # File doesn't exist anywhere
    output = capture_output do
      execute('source nonexistent_script_xyz.sh')
    end
    assert_match(/No such file or directory/, output)
  end

  def test_sourcepath_file_must_be_readable
    # Create a script in PATH directory without read permission
    script_path = File.join(@path_dir, 'unreadable.sh')
    File.write(script_path, "export VAR=test\n")
    File.chmod(0o000, script_path)

    ENV['PATH'] = "#{@path_dir}:#{@original_path}"

    # Should not find unreadable file
    output = capture_output do
      execute('source unreadable.sh')
    end
    assert_match(/No such file or directory/, output)
  ensure
    # Restore permissions for cleanup
    File.chmod(0o644, script_path) if File.exist?(script_path)
  end

  def test_sourcepath_disabled_falls_back_to_current_dir_only
    execute('shopt -u sourcepath')

    # Create script only in PATH
    File.write(File.join(@path_dir, 'pathonly.sh'), "export VAR=path\n")

    # Create script in current directory
    File.write(File.join(@tempdir, 'localonly.sh'), "export LOCAL_VAR=local\n")

    ENV['PATH'] = "#{@path_dir}:#{@original_path}"
    ENV['VAR'] = ''
    ENV['LOCAL_VAR'] = ''

    # PATH script should not be found
    output = capture_output do
      execute('source pathonly.sh')
    end
    assert_match(/No such file or directory/, output)
    assert_equal '', ENV['VAR']

    # Local script should still work
    execute('source localonly.sh')
    assert_equal 'local', ENV['LOCAL_VAR']
  end
end
