# frozen_string_literal: true

require_relative 'test_helper'

class TestCompleteFullquote < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_complete_fullquote_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  def complete_file(input)
    @repl.send(:complete_file, input)
  end

  def quote_completion_metacharacters(str)
    @repl.send(:quote_completion_metacharacters, str)
  end

  # complete_fullquote is enabled by default
  def test_complete_fullquote_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('complete_fullquote')
  end

  def test_complete_fullquote_can_be_disabled
    execute('shopt -u complete_fullquote')
    assert_false Rubish::Builtins.shopt_enabled?('complete_fullquote')
  end

  def test_complete_fullquote_can_be_enabled
    execute('shopt -u complete_fullquote')
    execute('shopt -s complete_fullquote')
    assert Rubish::Builtins.shopt_enabled?('complete_fullquote')
  end

  # Test quote_completion_metacharacters method
  def test_quote_space
    assert_equal 'hello\\ world', quote_completion_metacharacters('hello world')
  end

  def test_quote_multiple_spaces
    assert_equal 'a\\ b\\ c', quote_completion_metacharacters('a b c')
  end

  def test_quote_special_chars
    assert_equal 'file\\$var', quote_completion_metacharacters('file$var')
    assert_equal 'file\\&name', quote_completion_metacharacters('file&name')
    assert_equal 'file\\;name', quote_completion_metacharacters('file;name')
    assert_equal 'file\\|name', quote_completion_metacharacters('file|name')
  end

  def test_quote_parentheses
    assert_equal 'file\\(1\\)', quote_completion_metacharacters('file(1)')
  end

  def test_quote_brackets
    assert_equal 'file\\[1\\]', quote_completion_metacharacters('file[1]')
  end

  def test_quote_braces
    assert_equal 'file\\{a,b\\}', quote_completion_metacharacters('file{a,b}')
  end

  def test_quote_redirects
    assert_equal 'file\\<name\\>', quote_completion_metacharacters('file<name>')
  end

  def test_quote_quotes
    assert_equal 'file\\"name', quote_completion_metacharacters('file"name')
    assert_equal "file\\'name", quote_completion_metacharacters("file'name")
  end

  def test_quote_backslash
    assert_equal 'file\\\\name', quote_completion_metacharacters('file\\name')
  end

  def test_quote_glob_chars
    assert_equal 'file\\*', quote_completion_metacharacters('file*')
    assert_equal 'file\\?', quote_completion_metacharacters('file?')
  end

  def test_quote_backtick
    assert_equal 'file\\`cmd\\`', quote_completion_metacharacters('file`cmd`')
  end

  def test_quote_hash
    assert_equal 'file\\#comment', quote_completion_metacharacters('file#comment')
  end

  def test_quote_tilde
    assert_equal '\\~user', quote_completion_metacharacters('~user')
  end

  def test_quote_exclamation
    assert_equal 'file\\!name', quote_completion_metacharacters('file!name')
  end

  def test_no_quote_regular_chars
    assert_equal 'normalfile.txt', quote_completion_metacharacters('normalfile.txt')
    assert_equal 'path/to/file', quote_completion_metacharacters('path/to/file')
    assert_equal 'file-name_123', quote_completion_metacharacters('file-name_123')
  end

  # Test complete_file with complete_fullquote enabled
  def test_complete_file_quotes_spaces
    FileUtils.touch('file with spaces.txt')

    candidates = complete_file('file')
    assert_includes candidates, 'file\\ with\\ spaces.txt'
  end

  def test_complete_file_quotes_special_chars
    FileUtils.touch('file$dollar.txt')

    candidates = complete_file('file')
    assert_includes candidates, 'file\\$dollar.txt'
  end

  def test_complete_file_quotes_parentheses
    FileUtils.touch('file(1).txt')

    candidates = complete_file('file')
    assert_includes candidates, 'file\\(1\\).txt'
  end

  # Test complete_file with complete_fullquote disabled
  def test_complete_file_no_quote_when_disabled
    execute('shopt -u complete_fullquote')
    FileUtils.touch('file with spaces.txt')

    candidates = complete_file('file')
    assert_includes candidates, 'file with spaces.txt'
  end

  def test_complete_file_no_quote_special_chars_when_disabled
    execute('shopt -u complete_fullquote')
    FileUtils.touch('file$dollar.txt')

    candidates = complete_file('file')
    assert_includes candidates, 'file$dollar.txt'
  end

  # Test directories
  def test_complete_directory_quotes_spaces
    FileUtils.mkdir('dir with spaces')

    candidates = complete_file('dir')
    assert_includes candidates, 'dir\\ with\\ spaces/'
  end

  def test_complete_directory_no_quote_when_disabled
    execute('shopt -u complete_fullquote')
    FileUtils.mkdir('dir with spaces')

    candidates = complete_file('dir')
    assert_includes candidates, 'dir with spaces/'
  end

  # Test that regular files are not affected
  def test_complete_regular_file_unchanged
    FileUtils.touch('normalfile.txt')

    candidates = complete_file('normal')
    assert_includes candidates, 'normalfile.txt'
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt complete_fullquote')
    end
    assert_match(/complete_fullquote/, output)
    assert_match(/on/, output)

    execute('shopt -u complete_fullquote')

    output = capture_output do
      execute('shopt complete_fullquote')
    end
    assert_match(/complete_fullquote/, output)
    assert_match(/off/, output)
  end
end
