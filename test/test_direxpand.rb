# frozen_string_literal: true

require_relative 'test_helper'

class TestDirexpand < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_direxpand_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  def expand_for_completion(input)
    @repl.send(:expand_for_completion, input)
  end

  def complete_file(input)
    @repl.send(:complete_file, input)
  end

  # direxpand is disabled by default
  def test_direxpand_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('direxpand')
  end

  def test_direxpand_can_be_enabled
    execute('shopt -s direxpand')
    assert Rubish::Builtins.shopt_enabled?('direxpand')
  end

  def test_direxpand_can_be_disabled
    execute('shopt -s direxpand')
    execute('shopt -u direxpand')
    assert_false Rubish::Builtins.shopt_enabled?('direxpand')
  end

  # Test expand_for_completion helper method
  def test_expand_tilde_alone
    result = expand_for_completion('~')
    assert_equal Dir.home, result
  end

  def test_expand_tilde_with_path
    result = expand_for_completion('~/foo')
    assert_equal "#{Dir.home}/foo", result
  end

  def test_expand_tilde_with_nested_path
    result = expand_for_completion('~/foo/bar')
    assert_equal "#{Dir.home}/foo/bar", result
  end

  def test_expand_tilde_username
    # This test uses the current user
    username = ENV['USER'] || ENV['LOGNAME']
    if username
      result = expand_for_completion("~#{username}/foo")
      assert_equal "#{Dir.home}/foo", result
    end
  end

  def test_expand_tilde_unknown_user
    # Unknown user should remain unchanged
    result = expand_for_completion('~unknownuser12345/foo')
    assert_equal '~unknownuser12345/foo', result
  end

  def test_expand_env_var_simple
    ENV['TEST_DIREXPAND_VAR'] = '/test/path'
    result = expand_for_completion('$TEST_DIREXPAND_VAR/foo')
    assert_equal '/test/path/foo', result
  ensure
    ENV.delete('TEST_DIREXPAND_VAR')
  end

  def test_expand_env_var_braces
    ENV['TEST_DIREXPAND_VAR'] = '/test/path'
    result = expand_for_completion('${TEST_DIREXPAND_VAR}/foo')
    assert_equal '/test/path/foo', result
  ensure
    ENV.delete('TEST_DIREXPAND_VAR')
  end

  def test_expand_env_var_undefined
    # Undefined variable should remain unchanged
    ENV.delete('UNDEFINED_VAR_12345')
    result = expand_for_completion('$UNDEFINED_VAR_12345/foo')
    assert_equal '$UNDEFINED_VAR_12345/foo', result
  end

  def test_expand_home_env_var
    result = expand_for_completion('$HOME/foo')
    assert_equal "#{ENV['HOME']}/foo", result
  end

  def test_no_expand_without_special_chars
    result = expand_for_completion('/usr/local/bin')
    assert_equal '/usr/local/bin', result
  end

  # Test complete_file behavior with direxpand
  def test_complete_file_without_direxpand_shows_tilde
    # Create a directory in home
    test_subdir = File.join(Dir.home, '.rubish_test_direxpand_temp')
    FileUtils.mkdir_p(test_subdir)

    begin
      # Without direxpand, ~ is expanded for globbing but results show ~/... form
      candidates = complete_file('~/.rubish_test_direxpand')
      assert_includes candidates, '~/.rubish_test_direxpand_temp/'
    ensure
      FileUtils.rm_rf(test_subdir)
    end
  end

  def test_complete_file_with_direxpand_expands_tilde
    execute('shopt -s direxpand')

    # Create a directory in home
    test_subdir = File.join(Dir.home, '.rubish_test_direxpand_temp2')
    FileUtils.mkdir_p(test_subdir)

    begin
      # With direxpand, tilde should be expanded in completion results
      candidates = complete_file('~/.rubish_test_direxpand')
      assert_includes candidates, "#{test_subdir}/"
    ensure
      FileUtils.rm_rf(test_subdir)
    end
  end

  def test_complete_file_with_env_var
    execute('shopt -s direxpand')

    # Create test directory structure
    testdir = File.join(@tempdir, 'envtest')
    FileUtils.mkdir_p(testdir)
    FileUtils.touch(File.join(testdir, 'file1.txt'))

    ENV['TEST_COMPLETE_DIR'] = testdir
    begin
      candidates = complete_file('$TEST_COMPLETE_DIR/file')
      assert_includes candidates, "#{testdir}/file1.txt"
    ensure
      ENV.delete('TEST_COMPLETE_DIR')
    end
  end

  def test_direxpand_with_current_dir
    execute('shopt -s direxpand')

    # Create test files
    FileUtils.touch('testfile1.txt')
    FileUtils.touch('testfile2.txt')

    candidates = complete_file('testfile')
    assert_includes candidates, 'testfile1.txt'
    assert_includes candidates, 'testfile2.txt'
  end

  def test_direxpand_with_directory
    execute('shopt -s direxpand')

    # Create test directory
    FileUtils.mkdir_p('subdir')
    FileUtils.touch('subdir/innerfile.txt')

    candidates = complete_file('subdir/')
    assert_includes candidates, 'subdir/innerfile.txt'
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt direxpand')
    end
    assert_match(/direxpand/, output)
    assert_match(/off/, output)

    execute('shopt -s direxpand')

    output = capture_output do
      execute('shopt direxpand')
    end
    assert_match(/direxpand/, output)
    assert_match(/on/, output)
  end
end
