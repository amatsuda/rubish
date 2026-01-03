# frozen_string_literal: true

require_relative 'test_helper'

class TestPushdPopd < Test::Unit::TestCase
  def setup
    @original_dir = Dir.pwd
    @tempdir = File.realpath(Dir.mktmpdir('rubish_pushd_test'))
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
  end

  def pwd
    File.realpath(Dir.pwd)
  end

  # pushd tests
  def test_pushd_with_directory
    Rubish::Builtins.run('pushd', [@subdir1])
    assert_equal @subdir1, pwd
    assert_equal [@tempdir], Rubish::Builtins.dir_stack
  end

  def test_pushd_multiple_directories
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    assert_equal @subdir2, pwd
    assert_equal [@subdir1, @tempdir], Rubish::Builtins.dir_stack
  end

  def test_pushd_swap
    Rubish::Builtins.run('pushd', [@subdir1])
    assert_equal @subdir1, pwd

    # pushd with no args swaps top two
    Rubish::Builtins.run('pushd', [])
    assert_equal @tempdir, pwd
    assert_equal [@subdir1], Rubish::Builtins.dir_stack
  end

  def test_pushd_no_args_empty_stack
    output = capture_output { Rubish::Builtins.run('pushd', []) }
    assert_match(/no other directory/, output)
  end

  def test_pushd_nonexistent_directory
    output = capture_output { Rubish::Builtins.run('pushd', ['/nonexistent/path']) }
    assert_match(/No such file or directory/, output)
  end

  def test_pushd_prints_stack
    output = capture_output { Rubish::Builtins.run('pushd', [@subdir1]) }
    assert_match(/dir1/, output)
  end

  # popd tests
  def test_popd
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('popd', [])
    assert_equal @tempdir, pwd
    assert_equal [], Rubish::Builtins.dir_stack
  end

  def test_popd_multiple
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])

    Rubish::Builtins.run('popd', [])
    assert_equal @subdir1, pwd

    Rubish::Builtins.run('popd', [])
    assert_equal @tempdir, pwd
  end

  def test_popd_empty_stack
    output = capture_output { Rubish::Builtins.run('popd', []) }
    assert_match(/directory stack empty/, output)
  end

  def test_popd_prints_stack
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    output = capture_output { Rubish::Builtins.run('popd', []) }
    assert_match(/dir1/, output)
  end

  # dirs tests
  def test_dirs_empty_stack
    output = capture_output { Rubish::Builtins.run('dirs', []) }
    # Should show current directory
    assert_match(/rubish_pushd_test/, output)
  end

  def test_dirs_with_stack
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    output = capture_output { Rubish::Builtins.run('dirs', []) }
    assert_match(/dir2/, output)
    assert_match(/dir1/, output)
  end

  def test_dirs_tilde_expansion
    # cd to home and push
    home = ENV['HOME']
    Dir.chdir(home)
    Rubish::Builtins.run('pushd', [@subdir1])
    output = capture_output { Rubish::Builtins.run('dirs', []) }
    assert_match(/~/, output)
  end
end
