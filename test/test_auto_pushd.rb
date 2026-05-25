# frozen_string_literal: true

require_relative 'test_helper'

class TestAutoPushd < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_dir = Dir.pwd
    @original_zsh_options = Rubish::Builtins.current_state.zsh_options.dup
    @tempdir = File.realpath(Dir.mktmpdir('rubish_auto_pushd_test'))
    @subdir1 = File.join(@tempdir, 'dir1')
    @subdir2 = File.join(@tempdir, 'dir2')
    FileUtils.mkdir_p(@subdir1)
    FileUtils.mkdir_p(@subdir2)
    Rubish::Builtins.clear_dir_stack
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.clear_dir_stack
    Rubish::Builtins.current_state.zsh_options.clear
    @original_zsh_options.each { |k, v| Rubish::Builtins.current_state.zsh_options[k] = v }
  end

  def test_auto_pushd_off_by_default
    execute("cd #{@subdir1}")
    assert_equal [], Rubish::Builtins.current_state.dir_stack
  end

  def test_auto_pushd_pushes_on_cd
    execute('setopt auto_pushd')
    execute("cd #{@subdir1}")
    assert_equal [@tempdir], Rubish::Builtins.current_state.dir_stack
  end

  def test_auto_pushd_multiple_cds_build_stack
    execute('setopt auto_pushd')
    execute("cd #{@subdir1}")
    execute("cd #{@subdir2}")
    assert_equal [@subdir1, @tempdir], Rubish::Builtins.current_state.dir_stack
  end

  def test_unsetopt_disables_auto_pushd
    execute('setopt auto_pushd')
    execute("cd #{@subdir1}")
    assert_equal [@tempdir], Rubish::Builtins.current_state.dir_stack

    execute('unsetopt auto_pushd')
    execute("cd #{@subdir2}")
    assert_equal [@tempdir], Rubish::Builtins.current_state.dir_stack
  end

  def test_setopt_no_auto_pushd_disables
    execute('setopt auto_pushd')
    execute("cd #{@subdir1}")
    assert_equal [@tempdir], Rubish::Builtins.current_state.dir_stack

    execute('setopt no_auto_pushd')
    execute("cd #{@subdir2}")
    assert_equal [@tempdir], Rubish::Builtins.current_state.dir_stack
  end

  def test_auto_pushd_ignore_dups
    execute('setopt auto_pushd')
    execute('setopt pushd_ignore_dups')
    execute("cd #{@subdir1}")
    execute("cd #{@subdir2}")
    execute("cd #{@subdir1}")
    assert_equal [@subdir2, @tempdir], Rubish::Builtins.current_state.dir_stack
  end
end
