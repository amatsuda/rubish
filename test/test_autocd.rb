# frozen_string_literal: true

require_relative 'test_helper'

class TestAutocd < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_autocd_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
  end

  def test_autocd_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('autocd')
  end

  def test_autocd_does_not_cd_when_disabled
    subdir = File.join(@tempdir, 'subdir')
    FileUtils.mkdir_p(subdir)

    capture_stderr { execute('subdir') }
    # Should still be in tempdir since autocd is disabled
    assert_equal File.realpath(@tempdir), File.realpath(Dir.pwd)
  end

  def test_autocd_cds_to_directory_when_enabled
    subdir = File.join(@tempdir, 'subdir')
    FileUtils.mkdir_p(subdir)

    execute('shopt -s autocd')
    execute('subdir')
    assert_equal File.realpath(subdir), File.realpath(Dir.pwd)
  end

  def test_autocd_with_absolute_path
    subdir = File.join(@tempdir, 'absolute_test')
    FileUtils.mkdir_p(subdir)

    execute('shopt -s autocd')
    execute(subdir)
    assert_equal File.realpath(subdir), File.realpath(Dir.pwd)
  end

  def test_autocd_with_dotdot
    subdir = File.join(@tempdir, 'child')
    FileUtils.mkdir_p(subdir)
    Dir.chdir(subdir)

    execute('shopt -s autocd')
    execute('..')
    assert_equal File.realpath(@tempdir), File.realpath(Dir.pwd)
  end

  def test_autocd_with_dot
    execute('shopt -s autocd')
    execute('.')
    assert_equal File.realpath(@tempdir), File.realpath(Dir.pwd)
  end

  def test_autocd_does_not_affect_commands_with_args
    subdir = File.join(@tempdir, 'subdir')
    FileUtils.mkdir_p(subdir)

    execute('shopt -s autocd')
    # This should try to run 'subdir' with arg 'foo', not cd
    capture_stderr { execute('subdir foo') }
    # Should still be in tempdir
    assert_equal File.realpath(@tempdir), File.realpath(Dir.pwd)
  end

  def test_autocd_does_not_affect_nonexistent_directory
    execute('shopt -s autocd')
    capture_stderr { execute('nonexistent_dir') }
    # Should still be in tempdir
    assert_equal File.realpath(@tempdir), File.realpath(Dir.pwd)
  end

  def test_autocd_with_tilde_expansion
    # Create a directory that we can test with
    subdir = File.join(@tempdir, 'tildetest')
    FileUtils.mkdir_p(subdir)

    execute('shopt -s autocd')
    execute('tildetest')
    assert_equal File.realpath(subdir), File.realpath(Dir.pwd)
  end

  def test_autocd_nested_directories
    nested = File.join(@tempdir, 'a', 'b', 'c')
    FileUtils.mkdir_p(nested)

    execute('shopt -s autocd')
    execute('a/b/c')
    assert_equal File.realpath(nested), File.realpath(Dir.pwd)
  end
end
