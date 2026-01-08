# frozen_string_literal: true

require_relative 'test_helper'

class TestGLOBSORT < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_globsort_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def glob(pattern)
    @repl.send(:__glob, pattern)
  end

  # Default behavior (name sort)

  def test_default_sort_is_alphabetical
    FileUtils.touch('charlie.txt')
    FileUtils.touch('alpha.txt')
    FileUtils.touch('bravo.txt')
    ENV.delete('GLOBSORT')

    results = glob('*.txt')

    assert_equal ['alpha.txt', 'bravo.txt', 'charlie.txt'], results
  end

  def test_globsort_empty_is_alphabetical
    FileUtils.touch('zebra.txt')
    FileUtils.touch('apple.txt')
    ENV['GLOBSORT'] = ''

    results = glob('*.txt')

    assert_equal ['apple.txt', 'zebra.txt'], results
  end

  def test_globsort_name_is_alphabetical
    FileUtils.touch('zebra.txt')
    FileUtils.touch('apple.txt')
    FileUtils.touch('mango.txt')
    ENV['GLOBSORT'] = 'name'

    results = glob('*.txt')

    assert_equal ['apple.txt', 'mango.txt', 'zebra.txt'], results
  end

  # nosort

  def test_globsort_nosort_preserves_order
    # Create files in specific order
    FileUtils.touch('file3.txt')
    FileUtils.touch('file1.txt')
    FileUtils.touch('file2.txt')
    ENV['GLOBSORT'] = 'nosort'

    results = glob('*.txt')

    # With nosort, we just verify all files are present (order depends on filesystem)
    assert_equal 3, results.length
    assert_includes results, 'file1.txt'
    assert_includes results, 'file2.txt'
    assert_includes results, 'file3.txt'
  end

  # size sort

  def test_globsort_size_smallest_first
    File.write('small.txt', 'a')
    File.write('medium.txt', 'a' * 100)
    File.write('large.txt', 'a' * 1000)
    ENV['GLOBSORT'] = 'size'

    results = glob('*.txt')

    assert_equal ['small.txt', 'medium.txt', 'large.txt'], results
  end

  def test_globsort_size_reverse_largest_first
    File.write('small.txt', 'a')
    File.write('medium.txt', 'a' * 100)
    File.write('large.txt', 'a' * 1000)
    ENV['GLOBSORT'] = '-size'

    results = glob('*.txt')

    assert_equal ['large.txt', 'medium.txt', 'small.txt'], results
  end

  # mtime sort

  def test_globsort_mtime_oldest_first
    File.write('old.txt', 'old')
    sleep 0.1
    File.write('middle.txt', 'middle')
    sleep 0.1
    File.write('new.txt', 'new')
    ENV['GLOBSORT'] = 'mtime'

    results = glob('*.txt')

    assert_equal ['old.txt', 'middle.txt', 'new.txt'], results
  end

  def test_globsort_mtime_reverse_newest_first
    File.write('old.txt', 'old')
    sleep 0.1
    File.write('middle.txt', 'middle')
    sleep 0.1
    File.write('new.txt', 'new')
    ENV['GLOBSORT'] = '-mtime'

    results = glob('*.txt')

    assert_equal ['new.txt', 'middle.txt', 'old.txt'], results
  end

  # atime sort

  def test_globsort_atime_sorts_by_access_time
    File.write('file1.txt', 'content1')
    File.write('file2.txt', 'content2')
    sleep 0.1
    # Access file1 to update atime
    File.read('file1.txt')
    ENV['GLOBSORT'] = 'atime'

    results = glob('*.txt')

    # file2 should come first (older atime)
    assert_equal 'file2.txt', results.first
  end

  # ctime sort

  def test_globsort_ctime_sorts_by_change_time
    File.write('file1.txt', 'content1')
    sleep 0.1
    File.write('file2.txt', 'content2')
    ENV['GLOBSORT'] = 'ctime'

    results = glob('*.txt')

    # file1 should come first (older ctime)
    assert_equal ['file1.txt', 'file2.txt'], results
  end

  def test_globsort_ctime_reverse
    File.write('file1.txt', 'content1')
    sleep 0.1
    File.write('file2.txt', 'content2')
    ENV['GLOBSORT'] = '-ctime'

    results = glob('*.txt')

    # file2 should come first (newer ctime)
    assert_equal ['file2.txt', 'file1.txt'], results
  end

  # extension sort

  def test_globsort_extension_sorts_by_extension
    FileUtils.touch('file.txt')
    FileUtils.touch('file.md')
    FileUtils.touch('file.rb')
    FileUtils.touch('file.c')
    ENV['GLOBSORT'] = 'extension'

    results = glob('file.*')

    assert_equal ['file.c', 'file.md', 'file.rb', 'file.txt'], results
  end

  def test_globsort_extension_reverse
    FileUtils.touch('file.txt')
    FileUtils.touch('file.md')
    FileUtils.touch('file.rb')
    FileUtils.touch('file.c')
    ENV['GLOBSORT'] = '-extension'

    results = glob('file.*')

    assert_equal ['file.txt', 'file.rb', 'file.md', 'file.c'], results
  end

  def test_globsort_extension_case_insensitive
    FileUtils.touch('file.TXT')
    FileUtils.touch('file.md')
    FileUtils.touch('file.Rb')
    ENV['GLOBSORT'] = 'extension'

    results = glob('file.*')

    # Should sort case-insensitively
    assert_equal ['file.md', 'file.Rb', 'file.TXT'], results
  end

  def test_globsort_extension_files_without_extension
    FileUtils.touch('Makefile')
    FileUtils.touch('README')
    FileUtils.touch('file.txt')
    ENV['GLOBSORT'] = 'extension'

    results = glob('*')

    # Files without extension should come first (empty extension)
    assert_equal 'Makefile', results.first
    assert_equal 'README', results[1]
    assert_equal 'file.txt', results.last
  end

  # blocks sort (may not work on all filesystems)

  def test_globsort_blocks
    File.write('tiny.txt', 'x')
    File.write('bigger.txt', 'x' * 10000)
    ENV['GLOBSORT'] = 'blocks'

    results = glob('*.txt')

    # Just verify it doesn't crash and returns results
    assert_equal 2, results.length
  end

  # Reverse flag

  def test_globsort_reverse_name
    FileUtils.touch('alpha.txt')
    FileUtils.touch('beta.txt')
    FileUtils.touch('gamma.txt')
    ENV['GLOBSORT'] = '-name'

    results = glob('*.txt')

    assert_equal ['gamma.txt', 'beta.txt', 'alpha.txt'], results
  end

  # numeric sort (bash 5.3)

  def test_globsort_numeric_sorts_naturally
    FileUtils.touch('file1.txt')
    FileUtils.touch('file2.txt')
    FileUtils.touch('file10.txt')
    FileUtils.touch('file20.txt')
    ENV['GLOBSORT'] = 'numeric'

    results = glob('*.txt')

    # Numeric sort: file1 < file2 < file10 < file20
    assert_equal ['file1.txt', 'file2.txt', 'file10.txt', 'file20.txt'], results
  end

  def test_globsort_numeric_vs_name_sort
    FileUtils.touch('file1.txt')
    FileUtils.touch('file10.txt')
    FileUtils.touch('file2.txt')

    # Name sort would give: file1, file10, file2
    ENV['GLOBSORT'] = 'name'
    name_results = glob('*.txt')
    assert_equal ['file1.txt', 'file10.txt', 'file2.txt'], name_results

    # Numeric sort should give: file1, file2, file10
    ENV['GLOBSORT'] = 'numeric'
    numeric_results = glob('*.txt')
    assert_equal ['file1.txt', 'file2.txt', 'file10.txt'], numeric_results
  end

  def test_globsort_numeric_with_mixed_content
    FileUtils.touch('img001.jpg')
    FileUtils.touch('img2.jpg')
    FileUtils.touch('img10.jpg')
    FileUtils.touch('photo1.jpg')
    ENV['GLOBSORT'] = 'numeric'

    results = glob('*.jpg')

    # Should sort by prefix first, then numerically within same prefix
    assert_equal ['img001.jpg', 'img2.jpg', 'img10.jpg', 'photo1.jpg'], results
  end

  def test_globsort_numeric_reverse
    FileUtils.touch('file1.txt')
    FileUtils.touch('file2.txt')
    FileUtils.touch('file10.txt')
    ENV['GLOBSORT'] = '-numeric'

    results = glob('*.txt')

    assert_equal ['file10.txt', 'file2.txt', 'file1.txt'], results
  end

  def test_globsort_numeric_no_numbers
    FileUtils.touch('alpha.txt')
    FileUtils.touch('beta.txt')
    FileUtils.touch('gamma.txt')
    ENV['GLOBSORT'] = 'numeric'

    results = glob('*.txt')

    # Files without numbers should sort alphabetically
    assert_equal ['alpha.txt', 'beta.txt', 'gamma.txt'], results
  end

  def test_globsort_numeric_case_insensitive
    FileUtils.touch('File1.txt')
    FileUtils.touch('file2.txt')
    FileUtils.touch('FILE10.txt')
    ENV['GLOBSORT'] = 'numeric'

    results = glob('*.txt')

    # Case insensitive, so File1 < file2 < FILE10
    assert_equal ['File1.txt', 'file2.txt', 'FILE10.txt'], results
  end

  # none sort (bash 5.3 alias for nosort)

  def test_globsort_none_is_alias_for_nosort
    FileUtils.touch('file3.txt')
    FileUtils.touch('file1.txt')
    FileUtils.touch('file2.txt')
    ENV['GLOBSORT'] = 'none'

    results = glob('*.txt')

    # With none, just verify all files are present (order depends on filesystem)
    assert_equal 3, results.length
    assert_includes results, 'file1.txt'
    assert_includes results, 'file2.txt'
    assert_includes results, 'file3.txt'
  end

  def test_globsort_none_reverse_still_works
    FileUtils.touch('alpha.txt')
    FileUtils.touch('beta.txt')
    ENV['GLOBSORT'] = '-none'

    results = glob('*.txt')

    # -none should still return unsorted (reverse of unsorted is still unsorted order, just reversed)
    assert_equal 2, results.length
    assert_includes results, 'alpha.txt'
    assert_includes results, 'beta.txt'
  end

  # Unknown sort type

  def test_globsort_unknown_falls_back_to_name
    FileUtils.touch('zebra.txt')
    FileUtils.touch('apple.txt')
    ENV['GLOBSORT'] = 'unknowntype'

    results = glob('*.txt')

    # Should fall back to alphabetical
    assert_equal ['apple.txt', 'zebra.txt'], results
  end

  # Integration with other glob options

  def test_globsort_with_globignore
    FileUtils.touch('keep1.txt')
    FileUtils.touch('keep2.txt')
    FileUtils.touch('ignore.txt')
    ENV['GLOBSORT'] = '-name'
    ENV['GLOBIGNORE'] = 'ignore.txt'

    results = glob('*.txt')

    assert_equal ['keep2.txt', 'keep1.txt'], results
    assert_not_include results, 'ignore.txt'
  end

  def test_globsort_with_dotglob
    FileUtils.touch('.hidden')
    FileUtils.touch('visible')
    FileUtils.touch('alpha')
    Rubish::Builtins.set_options['dotglob'] = true
    ENV['GLOBSORT'] = 'name'

    results = glob('*')

    Rubish::Builtins.set_options['dotglob'] = false

    # .hidden should come first alphabetically (. sorts before letters)
    assert_equal '.hidden', results.first
    assert_includes results, 'alpha'
    assert_includes results, 'visible'
  end

  def test_globsort_with_nullglob_empty_result
    ENV['GLOBSORT'] = 'size'
    Rubish::Builtins.set_options['nullglob'] = true

    results = glob('nonexistent*.xyz')

    Rubish::Builtins.set_options['nullglob'] = false

    assert_equal [], results
  end

  # Via execute

  def test_globsort_via_execute
    File.write('small.txt', 'a')
    File.write('large.txt', 'a' * 1000)
    ENV['GLOBSORT'] = '-size'

    output_file = File.join(@tempdir, 'output.txt')
    execute("echo *.txt > #{output_file}")

    output = File.read(output_file).strip
    # large.txt should come first with -size
    assert_match(/^large\.txt/, output)
  end

  # Edge cases

  def test_globsort_single_file
    FileUtils.touch('only.txt')
    ENV['GLOBSORT'] = 'size'

    results = glob('*.txt')

    assert_equal ['only.txt'], results
  end

  def test_globsort_with_directories
    FileUtils.mkdir('dir_a')
    FileUtils.mkdir('dir_b')
    FileUtils.touch('file_c')
    ENV['GLOBSORT'] = 'name'

    results = glob('*')

    assert_equal ['dir_a', 'dir_b', 'file_c'], results
  end

  def test_globsort_preserves_path
    FileUtils.mkdir('subdir')
    File.write('subdir/beta.txt', 'b')
    File.write('subdir/alpha.txt', 'a')
    ENV['GLOBSORT'] = 'name'

    results = glob('subdir/*.txt')

    assert_equal ['subdir/alpha.txt', 'subdir/beta.txt'], results
  end
end
