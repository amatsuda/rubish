# frozen_string_literal: true

require_relative 'test_helper'

class TestPushdPopd < Test::Unit::TestCase
  def setup
    @original_dir = Dir.pwd
    @tempdir = File.realpath(Dir.mktmpdir('rubish_pushd_test'))
    @subdir1 = File.join(@tempdir, 'dir1')
    @subdir2 = File.join(@tempdir, 'dir2')
    @subdir3 = File.join(@tempdir, 'dir3')
    FileUtils.mkdir_p(@subdir1)
    FileUtils.mkdir_p(@subdir2)
    FileUtils.mkdir_p(@subdir3)
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

  # pushd -n tests

  def test_pushd_n_no_cd
    Rubish::Builtins.run('pushd', ['-n', @subdir1])
    # Should NOT have changed directory
    assert_equal @tempdir, pwd
    # But stack should have the directory
    assert_equal [@tempdir], Rubish::Builtins.dir_stack
  end

  def test_pushd_n_swap_no_cd
    Rubish::Builtins.run('pushd', [@subdir1])
    assert_equal @subdir1, pwd

    # Swap with -n should not change directory
    Rubish::Builtins.run('pushd', ['-n'])
    assert_equal @subdir1, pwd
    # Stack should have swapped
    assert_equal [@subdir1], Rubish::Builtins.dir_stack
  end

  # pushd +N/-N tests

  def test_pushd_plus_n_rotation
    # Build stack: current=tempdir, stack=[dir1, dir2]
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    # Now: current=dir2, stack=[dir1, tempdir]

    # +1 should rotate left by 1
    Rubish::Builtins.run('pushd', ['+1'])
    # dir1 should now be current
    assert_equal @subdir1, pwd
  end

  def test_pushd_plus_zero
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    # current=dir2, stack=[dir1, tempdir]

    # +0 should be a no-op (current stays current)
    Rubish::Builtins.run('pushd', ['+0'])
    assert_equal @subdir2, pwd
  end

  def test_pushd_minus_n_rotation
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    # current=dir2, stack=[dir1, tempdir]
    # full_stack = [dir2, dir1, tempdir]

    # -0 should bring last element (tempdir) to front
    Rubish::Builtins.run('pushd', ['-0'])
    assert_equal @tempdir, pwd
  end

  def test_pushd_out_of_range
    Rubish::Builtins.run('pushd', [@subdir1])
    # stack has 2 elements total

    output = capture_output do
      result = Rubish::Builtins.run('pushd', ['+5'])
      assert_false result
    end
    assert_match(/out of range/, output)
  end

  def test_pushd_n_with_rotation
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    original_pwd = pwd

    # -n +1 should rotate stack but not change directory
    Rubish::Builtins.run('pushd', ['-n', '+1'])
    assert_equal original_pwd, pwd
  end

  # popd -n tests

  def test_popd_n_no_cd
    Rubish::Builtins.run('pushd', [@subdir1])
    assert_equal @subdir1, pwd

    # popd -n should not change directory
    Rubish::Builtins.run('popd', ['-n'])
    assert_equal @subdir1, pwd
    # Stack should be empty
    assert_equal [], Rubish::Builtins.dir_stack
  end

  # popd +N/-N tests

  def test_popd_plus_zero
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    # current=dir2, stack=[dir1, tempdir]

    # +0 removes current directory, cd to next
    Rubish::Builtins.run('popd', ['+0'])
    assert_equal @subdir1, pwd
    assert_equal [@tempdir], Rubish::Builtins.dir_stack
  end

  def test_popd_plus_one
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    # current=dir2, stack=[dir1, tempdir]
    # full_stack = [dir2, dir1, tempdir]

    # +1 removes dir1 from stack
    Rubish::Builtins.run('popd', ['+1'])
    assert_equal @subdir2, pwd
    assert_equal [@tempdir], Rubish::Builtins.dir_stack
  end

  def test_popd_minus_zero
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    # current=dir2, stack=[dir1, tempdir]
    # full_stack = [dir2, dir1, tempdir]

    # -0 removes last element (tempdir)
    Rubish::Builtins.run('popd', ['-0'])
    assert_equal @subdir2, pwd
    assert_equal [@subdir1], Rubish::Builtins.dir_stack
  end

  def test_popd_out_of_range
    Rubish::Builtins.run('pushd', [@subdir1])
    # stack has 2 elements

    output = capture_output do
      result = Rubish::Builtins.run('popd', ['+5'])
      assert_false result
    end
    assert_match(/out of range/, output)
  end

  def test_popd_n_with_index
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    original_pwd = pwd

    # -n +1 should remove from stack but not change directory
    Rubish::Builtins.run('popd', ['-n', '+1'])
    assert_equal original_pwd, pwd
  end

  def test_popd_invalid_arg
    output = capture_output do
      result = Rubish::Builtins.run('popd', ['invalid'])
      assert_false result
    end
    assert_match(/invalid argument/, output)
  end

  # Help documentation tests

  def test_pushd_help_has_n_option
    help = Rubish::Builtins::BUILTIN_HELP['pushd']
    assert_not_nil help
    assert_match(/-n/, help[:synopsis])
    assert help[:options].key?('-n')
  end

  def test_popd_help_has_n_option
    help = Rubish::Builtins::BUILTIN_HELP['popd']
    assert_not_nil help
    assert_match(/-n/, help[:synopsis])
    assert help[:options].key?('-n')
  end

  # Complex scenarios

  def test_multiple_rotations
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    Rubish::Builtins.run('pushd', [@subdir3])
    # current=dir3, stack=[dir2, dir1, tempdir]

    # Rotate twice
    Rubish::Builtins.run('pushd', ['+1'])
    Rubish::Builtins.run('pushd', ['+1'])
    assert_equal @subdir1, pwd
  end

  def test_pushd_swap_after_rotation
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    # current=dir2, stack=[dir1, tempdir]

    # Swap
    Rubish::Builtins.run('pushd', [])
    assert_equal @subdir1, pwd
    assert_equal [@subdir2, @tempdir], Rubish::Builtins.dir_stack
  end
end
