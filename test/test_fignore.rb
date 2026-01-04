# frozen_string_literal: true

require_relative 'test_helper'

class TestFIGNORE < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_fignore_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def complete_file(input)
    @repl.send(:complete_file, input)
  end

  # Basic FIGNORE functionality

  def test_complete_without_fignore
    FileUtils.touch('file.txt')
    FileUtils.touch('file.o')
    FileUtils.touch('file.bak')
    ENV.delete('FIGNORE')

    results = complete_file('file')

    assert_equal ['file.bak', 'file.o', 'file.txt'], results
  end

  def test_fignore_single_suffix
    FileUtils.touch('main.c')
    FileUtils.touch('main.o')
    FileUtils.touch('helper.c')
    FileUtils.touch('helper.o')
    ENV['FIGNORE'] = '.o'

    results = complete_file('m')

    assert_equal ['main.c'], results
  end

  def test_fignore_multiple_suffixes
    FileUtils.touch('file.txt')
    FileUtils.touch('file.o')
    FileUtils.touch('file.bak')
    FileUtils.touch('file.tmp')
    ENV['FIGNORE'] = '.o:.bak:.tmp'

    results = complete_file('file')

    assert_equal ['file.txt'], results
  end

  def test_fignore_does_not_filter_directories
    FileUtils.mkdir('backup.bak')
    FileUtils.touch('file.bak')
    FileUtils.touch('file.txt')
    ENV['FIGNORE'] = '.bak'

    results = complete_file('')

    assert_includes results, 'backup.bak/'
    assert_includes results, 'file.txt'
    assert_not_include results, 'file.bak'
  end

  def test_fignore_shows_all_if_all_would_be_filtered
    FileUtils.touch('file.o')
    FileUtils.touch('file.bak')
    ENV['FIGNORE'] = '.o:.bak'

    results = complete_file('file')

    # All files would be filtered, so show them all
    assert_equal ['file.bak', 'file.o'], results
  end

  def test_fignore_empty_string
    FileUtils.touch('file.txt')
    FileUtils.touch('file.o')
    ENV['FIGNORE'] = ''

    results = complete_file('file')

    assert_equal ['file.o', 'file.txt'], results
  end

  def test_fignore_empty_entries_ignored
    FileUtils.touch('file.txt')
    FileUtils.touch('file.o')
    FileUtils.touch('file.bak')
    ENV['FIGNORE'] = '.o::.bak'  # Empty entry between colons

    results = complete_file('file')

    assert_equal ['file.txt'], results
  end

  def test_fignore_tilde_suffix
    FileUtils.touch('file.txt')
    FileUtils.touch('file.txt~')
    ENV['FIGNORE'] = '~'

    results = complete_file('file')

    assert_equal ['file.txt'], results
  end

  def test_fignore_with_path
    FileUtils.mkdir('subdir')
    FileUtils.touch('subdir/code.c')
    FileUtils.touch('subdir/code.o')
    ENV['FIGNORE'] = '.o'

    results = complete_file('subdir/code')

    assert_equal ['subdir/code.c'], results
  end

  def test_fignore_pyc_files
    FileUtils.touch('module.py')
    FileUtils.touch('module.pyc')
    FileUtils.touch('helper.py')
    FileUtils.touch('helper.pyc')
    ENV['FIGNORE'] = '.pyc'

    results = complete_file('')

    assert_includes results, 'module.py'
    assert_includes results, 'helper.py'
    assert_not_include results, 'module.pyc'
    assert_not_include results, 'helper.pyc'
  end

  def test_fignore_common_development_suffixes
    FileUtils.touch('app.js')
    FileUtils.touch('app.js.map')
    FileUtils.touch('style.css')
    FileUtils.touch('style.css.map')
    FileUtils.touch('data.json')
    ENV['FIGNORE'] = '.map'

    results = complete_file('')

    assert_includes results, 'app.js'
    assert_includes results, 'style.css'
    assert_includes results, 'data.json'
    assert_not_include results, 'app.js.map'
    assert_not_include results, 'style.css.map'
  end

  def test_fignore_partial_match_does_not_filter
    FileUtils.touch('foo.txt')
    FileUtils.touch('foo.txta')  # Ends with 'a', not '.txt'
    ENV['FIGNORE'] = '.txt'

    results = complete_file('foo')

    # foo.txta should NOT be filtered (doesn't end with .txt)
    assert_equal ['foo.txta'], results
  end

  def test_fignore_case_sensitive
    FileUtils.touch('file.TXT')
    FileUtils.touch('file.txt')
    ENV['FIGNORE'] = '.txt'

    results = complete_file('file')

    # .TXT should not be filtered (case sensitive)
    assert_equal ['file.TXT'], results
  end

  # Integration with complete method

  def test_fignore_via_complete
    FileUtils.touch('script.sh')
    FileUtils.touch('script.sh~')
    FileUtils.touch('backup.bak')
    ENV['FIGNORE'] = '~:.bak'

    # complete_file is called for file completion
    results = complete_file('script')

    assert_equal ['script.sh'], results
  end
end
