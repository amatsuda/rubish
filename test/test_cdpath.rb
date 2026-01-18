# frozen_string_literal: true

require_relative 'test_helper'

class TestCDPATH < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_cdpath_test')

    # Create test directory structure
    # /tempdir/
    #   dir1/
    #   dir2/
    #   search1/
    #     target/
    #   search2/
    #     other/
    #     target/
    FileUtils.mkdir_p(File.join(@tempdir, 'dir1'))
    FileUtils.mkdir_p(File.join(@tempdir, 'dir2'))
    FileUtils.mkdir_p(File.join(@tempdir, 'search1', 'target'))
    FileUtils.mkdir_p(File.join(@tempdir, 'search2', 'other'))
    FileUtils.mkdir_p(File.join(@tempdir, 'search2', 'target'))
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic CDPATH functionality

  def test_cd_without_cdpath_uses_current_dir
    Dir.chdir(@tempdir)
    ENV.delete('CDPATH')

    result = Rubish::Builtins.run_cd(['dir1'])

    assert result
    assert_equal real(File.join(@tempdir, 'dir1')), real(Dir.pwd)
  end

  def test_cd_with_cdpath_finds_directory
    Dir.chdir(@tempdir)
    ENV['CDPATH'] = File.join(@tempdir, 'search1')

    output = capture_output { Rubish::Builtins.run_cd(['target']) }

    assert_equal real(File.join(@tempdir, 'search1', 'target')), real(Dir.pwd)
    # Should print the directory when found via CDPATH
    assert_match(/search1\/target/, output)
  end

  def test_cd_with_cdpath_prefers_current_dir
    Dir.chdir(@tempdir)
    # Create target in current directory too
    FileUtils.mkdir_p(File.join(@tempdir, 'target'))
    ENV['CDPATH'] = File.join(@tempdir, 'search1')

    output = capture_output { Rubish::Builtins.run_cd(['target']) }

    # Should use current directory's target, not CDPATH
    assert_equal real(File.join(@tempdir, 'target')), real(Dir.pwd)
    # Should NOT print directory (not found via CDPATH)
    assert_equal '', output
  end

  def test_cd_with_cdpath_searches_in_order
    Dir.chdir(@tempdir)
    # Both search1 and search2 have 'target'
    ENV['CDPATH'] = "#{File.join(@tempdir, 'search1')}:#{File.join(@tempdir, 'search2')}"

    Rubish::Builtins.run_cd(['target'])

    # Should find in search1 first
    assert_equal real(File.join(@tempdir, 'search1', 'target')), real(Dir.pwd)
  end

  def test_cd_with_cdpath_uses_second_path_if_first_fails
    Dir.chdir(@tempdir)
    # Only search2 has 'other'
    ENV['CDPATH'] = "#{File.join(@tempdir, 'search1')}:#{File.join(@tempdir, 'search2')}"

    Rubish::Builtins.run_cd(['other'])

    assert_equal real(File.join(@tempdir, 'search2', 'other')), real(Dir.pwd)
  end

  def test_cd_with_empty_cdpath_entry_means_current_dir
    Dir.chdir(@tempdir)
    # Empty entry (::) means current directory
    ENV['CDPATH'] = ":#{File.join(@tempdir, 'search1')}"

    # dir1 exists in current directory
    output = capture_output { Rubish::Builtins.run_cd(['dir1']) }

    assert_equal real(File.join(@tempdir, 'dir1')), real(Dir.pwd)
    # Empty path entry found it, so no output (same as current dir)
    assert_equal '', output
  end

  # Absolute paths ignore CDPATH

  def test_cd_absolute_path_ignores_cdpath
    Dir.chdir(@tempdir)
    ENV['CDPATH'] = '/nonexistent'
    target = File.join(@tempdir, 'dir1')

    Rubish::Builtins.run_cd([target])

    assert_equal real(target), real(Dir.pwd)
  end

  # Relative paths starting with . or .. ignore CDPATH

  def test_cd_dot_slash_ignores_cdpath
    Dir.chdir(@tempdir)
    ENV['CDPATH'] = File.join(@tempdir, 'search1')

    Rubish::Builtins.run_cd(['./dir1'])

    assert_equal real(File.join(@tempdir, 'dir1')), real(Dir.pwd)
  end

  def test_cd_dot_dot_slash_ignores_cdpath
    Dir.chdir(File.join(@tempdir, 'dir1'))
    ENV['CDPATH'] = '/nonexistent'

    Rubish::Builtins.run_cd(['../dir2'])

    assert_equal real(File.join(@tempdir, 'dir2')), real(Dir.pwd)
  end

  def test_cd_single_dot_ignores_cdpath
    Dir.chdir(@tempdir)
    ENV['CDPATH'] = '/nonexistent'

    Rubish::Builtins.run_cd(['.'])

    assert_equal real(@tempdir), real(Dir.pwd)
  end

  def test_cd_double_dot_ignores_cdpath
    Dir.chdir(File.join(@tempdir, 'dir1'))
    ENV['CDPATH'] = '/nonexistent'

    Rubish::Builtins.run_cd(['..'])

    assert_equal real(@tempdir), real(Dir.pwd)
  end

  # CDPATH with -P option

  def test_cd_cdpath_with_physical_option
    Dir.chdir(@tempdir)
    ENV['CDPATH'] = File.join(@tempdir, 'search1')

    Rubish::Builtins.run_cd(['-P', 'target'])

    # Should resolve to physical path
    assert_equal real(File.join(@tempdir, 'search1', 'target')), real(Dir.pwd)
  end

  # Directory not found

  def test_cd_not_found_with_cdpath
    Dir.chdir(@tempdir)
    ENV['CDPATH'] = File.join(@tempdir, 'search1')

    result = Rubish::Builtins.run_cd(['nonexistent'])

    assert_equal false, result
  end

  # Integration tests via execute

  def test_cdpath_via_execute
    Dir.chdir(@tempdir)
    ENV['CDPATH'] = File.join(@tempdir, 'search1')

    output = capture_output { execute('cd target') }

    assert_equal real(File.join(@tempdir, 'search1', 'target')), real(Dir.pwd)
    assert_match(/target/, output)
  end

  def test_cdpath_multiple_paths_via_execute
    Dir.chdir(@tempdir)
    ENV['CDPATH'] = "#{File.join(@tempdir, 'search1')}:#{File.join(@tempdir, 'search2')}"

    execute('cd other')

    assert_equal real(File.join(@tempdir, 'search2', 'other')), real(Dir.pwd)
  end

  # cd - tests (switch to OLDPWD)

  def test_cd_dash_switches_to_oldpwd
    Dir.chdir(@tempdir)
    dir1 = File.join(@tempdir, 'dir1')
    dir2 = File.join(@tempdir, 'dir2')

    Dir.chdir(dir1)
    ENV['OLDPWD'] = dir2

    output = capture_output { Rubish::Builtins.run_cd(['-']) }

    assert_equal real(dir2), real(Dir.pwd)
    # cd - should print the new directory
    assert_match(/dir2/, output)
  end

  def test_cd_dash_updates_oldpwd
    Dir.chdir(@tempdir)
    dir1 = File.join(@tempdir, 'dir1')
    dir2 = File.join(@tempdir, 'dir2')

    Dir.chdir(dir1)
    ENV['PWD'] = Dir.pwd  # Ensure PWD is set correctly
    ENV['OLDPWD'] = dir2

    Rubish::Builtins.run_cd(['-'])

    # OLDPWD should now be the previous directory (dir1)
    assert_equal real(dir1), real(ENV['OLDPWD'])
  end

  def test_cd_dash_toggle
    Dir.chdir(@tempdir)
    dir1 = File.join(@tempdir, 'dir1')
    dir2 = File.join(@tempdir, 'dir2')

    Dir.chdir(dir1)
    ENV['PWD'] = Dir.pwd  # Ensure PWD is set correctly
    ENV['OLDPWD'] = dir2

    # First cd - goes to dir2
    Rubish::Builtins.run_cd(['-'])
    assert_equal real(dir2), real(Dir.pwd)

    # Second cd - goes back to dir1
    Rubish::Builtins.run_cd(['-'])
    assert_equal real(dir1), real(Dir.pwd)

    # Third cd - goes back to dir2
    Rubish::Builtins.run_cd(['-'])
    assert_equal real(dir2), real(Dir.pwd)
  end

  def test_cd_dash_without_oldpwd_fails
    Dir.chdir(@tempdir)
    ENV.delete('OLDPWD')

    stderr_output = capture_stderr { result = Rubish::Builtins.run_cd(['-']) }

    assert_match(/OLDPWD not set/, stderr_output)
  end

  def test_cd_dash_with_empty_oldpwd_fails
    Dir.chdir(@tempdir)
    ENV['OLDPWD'] = ''

    stderr_output = capture_stderr { Rubish::Builtins.run_cd(['-']) }

    assert_match(/OLDPWD not set/, stderr_output)
  end

  def test_cd_dash_via_execute
    Dir.chdir(@tempdir)
    dir1 = File.join(@tempdir, 'dir1')
    dir2 = File.join(@tempdir, 'dir2')

    Dir.chdir(dir1)
    ENV['OLDPWD'] = dir2

    output = capture_output { execute('cd -') }

    assert_equal real(dir2), real(Dir.pwd)
    assert_match(/dir2/, output)
  end

  def test_cd_dash_with_physical_option
    Dir.chdir(@tempdir)
    dir1 = File.join(@tempdir, 'dir1')
    dir2 = File.join(@tempdir, 'dir2')

    Dir.chdir(dir1)
    ENV['OLDPWD'] = dir2

    Rubish::Builtins.run_cd(['-P', '-'])

    assert_equal real(dir2), real(Dir.pwd)
  end

  private

  # Helper to normalize paths (handle symlinks like /var -> /private/var on macOS)
  def real(path)
    File.realpath(path)
  end
end
