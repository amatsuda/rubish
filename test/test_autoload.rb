# frozen_string_literal: true

require_relative 'test_helper'

class TestAutoload < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_autoload_test')
    @fpath_dir = File.join(@tempdir, 'functions')
    FileUtils.mkdir_p(@fpath_dir)
    ENV['FPATH'] = @fpath_dir
    Rubish::Builtins.instance_variable_set(:@autoload_functions, {})
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.instance_variable_set(:@autoload_functions, {})
  end

  # Test autoload is a builtin
  def test_autoload_is_builtin
    assert Rubish::Builtins.builtin?('autoload')
  end

  # Test autoload marks function for loading
  def test_autoload_marks_function
    result = Rubish::Builtins.run('autoload', ['myfunc'])
    assert result
    assert Rubish::Builtins.autoload_pending?('myfunc')
  end

  # Test autoload with -U option
  def test_autoload_with_U_option
    result = Rubish::Builtins.run('autoload', ['-U', 'myfunc'])
    assert result
    assert Rubish::Builtins.autoload_pending?('myfunc')
  end

  # Test autoload with -Uz options (common zsh pattern)
  def test_autoload_with_Uz_options
    result = Rubish::Builtins.run('autoload', ['-Uz', 'compinit'])
    assert result
    assert Rubish::Builtins.autoload_pending?('compinit')
  end

  # Test autoload lists functions when no args
  def test_autoload_lists_functions
    Rubish::Builtins.run('autoload', ['func1'])
    Rubish::Builtins.run('autoload', ['func2'])

    output = capture_output { Rubish::Builtins.run('autoload', []) }
    assert_match(/func1/, output)
    assert_match(/func2/, output)
    assert_match(/not yet loaded/, output)
  end

  # Test autoload bad option
  def test_autoload_bad_option
    output = capture_output do
      result = Rubish::Builtins.run('autoload', ['-Q'])
      assert_false result
    end
    assert_match(/bad option/, output)
  end

  # Test fpath accessor
  def test_fpath_accessor
    ENV['FPATH'] = '/usr/share/zsh/functions:/usr/local/share/zsh/functions'
    fpath = Rubish::Builtins.fpath
    assert_equal ['/usr/share/zsh/functions', '/usr/local/share/zsh/functions'], fpath
  end

  # Test fpath with empty value
  def test_fpath_empty
    ENV.delete('FPATH')
    ENV.delete('fpath')
    assert_equal [], Rubish::Builtins.fpath
  end

  # Test fpath setter
  def test_fpath_setter
    Rubish::Builtins.fpath = ['/path/one', '/path/two']
    assert_equal '/path/one:/path/two', ENV['FPATH']
  end

  # Test autoload_pending? returns false for loaded function
  def test_autoload_pending_false_after_load
    # Create a function file
    File.write(File.join(@fpath_dir, 'testfunc'), 'echo "hello from testfunc"')

    Rubish::Builtins.run('autoload', ['testfunc'])
    assert Rubish::Builtins.autoload_pending?('testfunc')

    # Load the function
    Rubish::Builtins.load_autoload_function('testfunc')
    assert_false Rubish::Builtins.autoload_pending?('testfunc')
  end

  # Test autoload with +X loads immediately without executing
  def test_autoload_plus_X_loads_immediately
    # Create a function file
    File.write(File.join(@fpath_dir, 'myfunc'), 'echo "loaded"')

    # Mark for autoload first
    Rubish::Builtins.run('autoload', ['myfunc'])

    # Now load with +X
    result = Rubish::Builtins.run('autoload', ['+X', 'myfunc'])
    assert result
    assert_false Rubish::Builtins.autoload_pending?('myfunc')
  end

  # Test load_autoload_function returns false for missing file
  def test_load_autoload_function_missing_file
    Rubish::Builtins.run('autoload', ['nonexistent'])
    result = Rubish::Builtins.load_autoload_function('nonexistent')
    assert_false result
  end

  # Test multiple functions can be autoloaded
  def test_autoload_multiple_functions
    result = Rubish::Builtins.run('autoload', ['func1', 'func2', 'func3'])
    assert result
    assert Rubish::Builtins.autoload_pending?('func1')
    assert Rubish::Builtins.autoload_pending?('func2')
    assert Rubish::Builtins.autoload_pending?('func3')
  end

  # Test type identifies autoload as builtin
  def test_type_identifies_autoload_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['autoload']) }
    assert_match(/autoload is a shell builtin/, output)
  end

  # Test autoload via REPL
  def test_autoload_via_repl
    execute('autoload myfunc')
    assert Rubish::Builtins.autoload_pending?('myfunc')
  end
end
