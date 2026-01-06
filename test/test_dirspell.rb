# frozen_string_literal: true

require_relative 'test_helper'

class TestDirspell < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_dirspell_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
  end

  def complete_file(input)
    @repl.send(:complete_file, input)
  end

  def test_dirspell_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('dirspell')
  end

  def test_dirspell_no_correction_when_disabled
    FileUtils.mkdir_p('testdir')
    FileUtils.touch('testdir/file.txt')

    # Typo in directory name, dirspell disabled
    candidates = complete_file('tsetdir/file')
    assert_empty candidates
  end

  def test_dirspell_corrects_directory_transposition
    FileUtils.mkdir_p('testdir')
    FileUtils.touch('testdir/file.txt')

    execute('shopt -s dirspell')
    # Typo: 'tsetdir' instead of 'testdir'
    candidates = complete_file('tsetdir/file')
    assert_include candidates, 'testdir/file.txt'
  end

  def test_dirspell_corrects_directory_missing_char
    FileUtils.mkdir_p('documents')
    FileUtils.touch('documents/report.txt')

    execute('shopt -s dirspell')
    # Typo: 'docments' (missing 'u')
    candidates = complete_file('docments/rep')
    assert_include candidates, 'documents/report.txt'
  end

  def test_dirspell_corrects_directory_extra_char
    FileUtils.mkdir_p('src')
    FileUtils.touch('src/main.rb')

    execute('shopt -s dirspell')
    # Typo: 'srrc' (extra 'r')
    candidates = complete_file('srrc/main')
    assert_include candidates, 'src/main.rb'
  end

  def test_dirspell_corrects_directory_wrong_char
    FileUtils.mkdir_p('config')
    FileUtils.touch('config/settings.yml')

    execute('shopt -s dirspell')
    # Typo: 'canfig' ('o' -> 'a')
    candidates = complete_file('canfig/set')
    assert_include candidates, 'config/settings.yml'
  end

  def test_dirspell_no_correction_for_completely_wrong_name
    FileUtils.mkdir_p('testdir')
    FileUtils.touch('testdir/file.txt')

    execute('shopt -s dirspell')
    # Completely wrong directory name
    candidates = complete_file('xyz/file')
    assert_empty candidates
  end

  def test_dirspell_with_nested_path
    FileUtils.mkdir_p('parent/child')
    FileUtils.touch('parent/child/file.txt')

    execute('shopt -s dirspell')
    # Typo in nested directory: 'praent' instead of 'parent'
    candidates = complete_file('praent/child/fi')
    assert_include candidates, 'parent/child/file.txt'
  end

  def test_dirspell_exact_match_no_correction_needed
    FileUtils.mkdir_p('exact')
    FileUtils.touch('exact/file.txt')

    execute('shopt -s dirspell')
    # Exact directory name
    candidates = complete_file('exact/fi')
    assert_include candidates, 'exact/file.txt'
  end

  def test_dirspell_without_path_separator
    FileUtils.touch('somefile.txt')

    execute('shopt -s dirspell')
    # No path separator, dirspell should not apply
    candidates = complete_file('someflie')  # typo
    assert_empty candidates
  end

  def test_dirspell_with_multiple_files
    FileUtils.mkdir_p('mydir')
    FileUtils.touch('mydir/file1.txt')
    FileUtils.touch('mydir/file2.txt')
    FileUtils.touch('mydir/other.rb')

    execute('shopt -s dirspell')
    # Typo: 'mydri' instead of 'mydir'
    candidates = complete_file('mydri/file')
    assert_equal 2, candidates.size
    assert_include candidates, 'mydir/file1.txt'
    assert_include candidates, 'mydir/file2.txt'
  end

  def test_dirspell_returns_directories_with_slash
    FileUtils.mkdir_p('parent/subdir')

    execute('shopt -s dirspell')
    # Typo: 'praent' instead of 'parent'
    candidates = complete_file('praent/sub')
    assert_include candidates, 'parent/subdir/'
  end
end
