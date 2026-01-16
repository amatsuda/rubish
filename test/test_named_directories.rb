# frozen_string_literal: true

require_relative 'test_helper'

class TestNamedDirectories < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_named_dir_test')
    Rubish::Builtins.instance_variable_set(:@named_directories, {})
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.instance_variable_set(:@named_directories, {})
  end

  # ==========================================================================
  # hash -d tests
  # ==========================================================================

  def test_hash_d_defines_named_directory
    result = Rubish::Builtins.run('hash', ['-d', "proj=#{@tempdir}"])
    assert result
    assert_equal @tempdir, Rubish::Builtins.get_named_directory('proj')
  end

  def test_hash_d_multiple_definitions
    dir1 = File.join(@tempdir, 'dir1')
    dir2 = File.join(@tempdir, 'dir2')
    FileUtils.mkdir_p([dir1, dir2])

    result = Rubish::Builtins.run('hash', ['-d', "one=#{dir1}", "two=#{dir2}"])
    assert result
    assert_equal dir1, Rubish::Builtins.get_named_directory('one')
    assert_equal dir2, Rubish::Builtins.get_named_directory('two')
  end

  def test_hash_d_shows_named_directory
    Rubish::Builtins.set_named_directory('mydir', @tempdir)

    output = capture_output { Rubish::Builtins.run('hash', ['-d', 'mydir']) }
    assert_equal "#{@tempdir}\n", output
  end

  def test_hash_d_lists_all_named_directories
    Rubish::Builtins.set_named_directory('dir1', '/path/one')
    Rubish::Builtins.set_named_directory('dir2', '/path/two')

    output = capture_output { Rubish::Builtins.run('hash', ['-d']) }
    assert_match(/dir1=\/path\/one/, output)
    assert_match(/dir2=\/path\/two/, output)
  end

  def test_hash_d_empty_lists_nothing
    output = capture_output { Rubish::Builtins.run('hash', ['-d']) }
    assert_equal '', output
  end

  def test_hash_d_expands_tilde_in_path
    result = Rubish::Builtins.run('hash', ['-d', 'home=~'])
    assert result
    assert_equal Dir.home, Rubish::Builtins.get_named_directory('home')
  end

  def test_hash_d_via_repl
    execute("hash -d proj=#{@tempdir}")
    assert_equal @tempdir, Rubish::Builtins.get_named_directory('proj')
  end

  # ==========================================================================
  # Tilde expansion tests
  # ==========================================================================

  def test_tilde_expansion_with_named_directory
    Rubish::Builtins.set_named_directory('proj', @tempdir)

    expanded = @repl.send(:expand_tilde, '~proj')
    assert_equal @tempdir, expanded
  end

  def test_tilde_expansion_with_named_directory_and_subpath
    Rubish::Builtins.set_named_directory('proj', @tempdir)

    expanded = @repl.send(:expand_tilde, '~proj/subdir/file.txt')
    assert_equal "#{@tempdir}/subdir/file.txt", expanded
  end

  def test_tilde_expansion_falls_back_to_username
    # ~root should expand to root's home, not a named directory
    expanded = @repl.send(:expand_tilde, '~root')
    # On most systems, root exists
    begin
      expected = Dir.home('root')
      assert_equal expected, expanded
    rescue ArgumentError
      # root user doesn't exist on this system, skip
      omit 'root user not found on this system'
    end
  end

  def test_tilde_expansion_named_directory_takes_precedence
    # If both a named directory and a user exist with the same name,
    # named directory takes precedence
    username = ENV['USER'] || 'testuser'
    Rubish::Builtins.set_named_directory(username, @tempdir)

    expanded = @repl.send(:expand_tilde, "~#{username}")
    assert_equal @tempdir, expanded
  end

  def test_tilde_expansion_unknown_name
    # Unknown name that's neither a named directory nor a user
    expanded = @repl.send(:expand_tilde, '~nonexistent_user_xyz123')
    # Should be kept literal
    assert_equal '~nonexistent_user_xyz123', expanded
  end

  # ==========================================================================
  # Integration tests
  # ==========================================================================

  def test_cd_to_named_directory
    subdir = File.join(@tempdir, 'myproject')
    FileUtils.mkdir_p(subdir)
    Rubish::Builtins.set_named_directory('proj', subdir)

    execute('cd ~proj')
    # Use realpath to resolve symlinks (macOS /var -> /private/var)
    assert_equal File.realpath(subdir), File.realpath(Dir.pwd)
  end

  def test_cd_to_named_directory_subpath
    subdir = File.join(@tempdir, 'myproject', 'src')
    FileUtils.mkdir_p(subdir)
    Rubish::Builtins.set_named_directory('proj', File.join(@tempdir, 'myproject'))

    execute('cd ~proj/src')
    # Use realpath to resolve symlinks (macOS /var -> /private/var)
    assert_equal File.realpath(subdir), File.realpath(Dir.pwd)
  end

  # ==========================================================================
  # API tests
  # ==========================================================================

  def test_get_named_directory
    Rubish::Builtins.instance_variable_get(:@named_directories)['test'] = '/test/path'
    assert_equal '/test/path', Rubish::Builtins.get_named_directory('test')
  end

  def test_get_named_directory_not_found
    assert_nil Rubish::Builtins.get_named_directory('nonexistent')
  end

  def test_set_named_directory
    Rubish::Builtins.set_named_directory('mydir', '/my/path')
    assert_equal '/my/path', Rubish::Builtins.named_directories['mydir']
  end

  def test_remove_named_directory
    Rubish::Builtins.set_named_directory('mydir', '/my/path')
    Rubish::Builtins.remove_named_directory('mydir')
    assert_nil Rubish::Builtins.get_named_directory('mydir')
  end
end
