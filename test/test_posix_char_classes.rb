# frozen_string_literal: true

require_relative 'test_helper'

class TestPosixCharClasses < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_posix_test')

    # Create test files with various naming patterns
    # Avoid case-conflicts for macOS (case-insensitive file system)
    FileUtils.touch(File.join(@tempdir, 'file1.txt'))
    FileUtils.touch(File.join(@tempdir, 'file2.txt'))
    FileUtils.touch(File.join(@tempdir, 'file3.txt'))
    FileUtils.touch(File.join(@tempdir, 'fileA.txt'))
    FileUtils.touch(File.join(@tempdir, 'fileB.txt'))
    FileUtils.touch(File.join(@tempdir, 'file_.txt'))
    FileUtils.touch(File.join(@tempdir, 'lower.rb'))
    FileUtils.touch(File.join(@tempdir, 'Upper.rb'))
    FileUtils.touch(File.join(@tempdir, 'Mixed123.rb'))
    FileUtils.touch(File.join(@tempdir, 'alpha99.dat'))
    FileUtils.touch(File.join(@tempdir, 'Zulu88.dat'))
    FileUtils.touch(File.join(@tempdir, 'data_file.csv'))
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test expand_posix_classes helper method directly
  def test_expand_posix_digit
    result = @repl.send(:expand_posix_classes, '[[:digit:]]')
    assert_equal '[0-9]', result
  end

  def test_expand_posix_alpha
    result = @repl.send(:expand_posix_classes, '[[:alpha:]]')
    assert_equal '[a-zA-Z]', result
  end

  def test_expand_posix_alnum
    result = @repl.send(:expand_posix_classes, '[[:alnum:]]')
    assert_equal '[a-zA-Z0-9]', result
  end

  def test_expand_posix_lower
    result = @repl.send(:expand_posix_classes, '[[:lower:]]')
    assert_equal '[a-z]', result
  end

  def test_expand_posix_upper
    result = @repl.send(:expand_posix_classes, '[[:upper:]]')
    assert_equal '[A-Z]', result
  end

  def test_expand_posix_space
    result = @repl.send(:expand_posix_classes, '[[:space:]]')
    assert_equal '[ \\t\\n\\r\\f\\v]', result
  end

  def test_expand_posix_xdigit
    result = @repl.send(:expand_posix_classes, '[[:xdigit:]]')
    assert_equal '[0-9A-Fa-f]', result
  end

  def test_expand_posix_word
    result = @repl.send(:expand_posix_classes, '[[:word:]]')
    assert_equal '[a-zA-Z0-9_]', result
  end

  def test_expand_posix_blank
    result = @repl.send(:expand_posix_classes, '[[:blank:]]')
    assert_equal '[ \t]', result
  end

  def test_expand_posix_punct
    result = @repl.send(:expand_posix_classes, '[[:punct:]]')
    assert_match(/\[.*\]/, result)
  end

  # Test negation
  def test_expand_posix_negated_with_caret
    result = @repl.send(:expand_posix_classes, '[^[:digit:]]')
    assert_equal '[^0-9]', result
  end

  def test_expand_posix_negated_with_bang
    result = @repl.send(:expand_posix_classes, '[![:digit:]]')
    assert_equal '[!0-9]', result
  end

  # Test multiple classes in one bracket
  def test_expand_multiple_posix_classes
    result = @repl.send(:expand_posix_classes, '[[:alpha:][:digit:]]')
    assert_equal '[a-zA-Z0-9]', result
  end

  # Test mixed with regular characters
  def test_expand_posix_mixed_with_chars
    result = @repl.send(:expand_posix_classes, '[a[:digit:]]')
    assert_equal '[a0-9]', result
  end

  def test_expand_posix_mixed_with_range
    result = @repl.send(:expand_posix_classes, '[[:digit:]a-z]')
    assert_equal '[0-9a-z]', result
  end

  # Test pattern without POSIX classes (should remain unchanged)
  def test_expand_no_posix_unchanged
    result = @repl.send(:expand_posix_classes, '[abc]')
    assert_equal '[abc]', result
  end

  def test_expand_no_bracket_unchanged
    result = @repl.send(:expand_posix_classes, 'hello')
    assert_equal 'hello', result
  end

  # Test unknown class (should remain as-is)
  def test_expand_unknown_class
    result = @repl.send(:expand_posix_classes, '[[:unknown:]]')
    assert_equal '[[:unknown:]]', result
  end

  # Test __glob with POSIX classes
  def test_glob_digit_class
    matches = @repl.send(:__glob, File.join(@tempdir, 'file[[:digit:]].txt'))
    assert_equal 3, matches.length
    assert matches.any? { |m| m.end_with?('file1.txt') }
    assert matches.any? { |m| m.end_with?('file2.txt') }
    assert matches.any? { |m| m.end_with?('file3.txt') }
  end

  def test_glob_alpha_class
    matches = @repl.send(:__glob, File.join(@tempdir, 'file[[:alpha:]].txt'))
    assert_equal 2, matches.length
    assert matches.any? { |m| m.end_with?('fileA.txt') }
    assert matches.any? { |m| m.end_with?('fileB.txt') }
  end

  def test_glob_upper_class
    matches = @repl.send(:__glob, File.join(@tempdir, 'file[[:upper:]].txt'))
    assert_equal 2, matches.length
    assert matches.any? { |m| m.end_with?('fileA.txt') }
    assert matches.any? { |m| m.end_with?('fileB.txt') }
  end

  def test_glob_lower_class
    matches = @repl.send(:__glob, File.join(@tempdir, '[[:lower:]]*.rb'))
    assert matches.any? { |m| m.end_with?('lower.rb') }
    # Note: On case-insensitive file systems (macOS), Upper.rb may also match
    # because the file system treats 'U' and 'u' as equivalent
  end

  def test_glob_alnum_class
    matches = @repl.send(:__glob, File.join(@tempdir, 'file[[:alnum:]].txt'))
    # Should match file1.txt, file2.txt, file3.txt, fileA.txt, fileB.txt
    assert_equal 5, matches.length
  end

  def test_glob_word_class
    matches = @repl.send(:__glob, File.join(@tempdir, 'file[[:word:]].txt'))
    # Should match file1, file2, file3, fileA, fileB, file_
    assert_equal 6, matches.length
    assert matches.any? { |m| m.end_with?('file_.txt') }
  end

  def test_glob_negated_digit
    matches = @repl.send(:__glob, File.join(@tempdir, 'file[^[:digit:]].txt'))
    # Should match fileA, fileB, file_ (not file1, file2, file3)
    assert_equal 3, matches.length
    assert matches.none? { |m| m =~ /file[0-9]\.txt/ }
  end

  # Test execution via REPL
  def test_posix_digit_execution
    Dir.chdir(@tempdir) do
      execute("echo file[[:digit:]].txt > #{output_file}")
    end
    content = File.read(output_file)
    assert_match(/file1\.txt/, content)
    assert_match(/file2\.txt/, content)
    assert_match(/file3\.txt/, content)
    assert_no_match(/fileA\.txt/, content)
  end

  def test_posix_alpha_execution
    Dir.chdir(@tempdir) do
      execute("echo file[[:alpha:]].txt > #{output_file}")
    end
    content = File.read(output_file)
    assert_match(/fileA\.txt/, content)
    assert_match(/fileB\.txt/, content)
    assert_no_match(/file1\.txt/, content)
  end

  def test_posix_upper_execution
    Dir.chdir(@tempdir) do
      execute("echo [[:upper:]]*.rb > #{output_file}")
    end
    content = File.read(output_file)
    assert_match(/Upper\.rb/, content)
    assert_match(/Mixed123\.rb/, content)
    # Note: On case-insensitive file systems, lower.rb may also match
  end

  def test_posix_alnum_execution
    Dir.chdir(@tempdir) do
      execute("echo [[:alnum:]]*.dat > #{output_file}")
    end
    content = File.read(output_file)
    assert_match(/alpha99\.dat/, content)
    assert_match(/Zulu88\.dat/, content)
  end

  # Test in for loop
  def test_posix_in_for_loop
    Dir.chdir(@tempdir) do
      execute("for f in file[[:digit:]].txt; do echo $f >> #{output_file}; done")
    end
    content = File.read(output_file)
    lines = content.lines.map(&:chomp)
    assert lines.include?('file1.txt')
    assert lines.include?('file2.txt')
    assert lines.include?('file3.txt')
    assert_equal 3, lines.length
  end

  # Test with absolute path
  def test_posix_absolute_path
    execute("echo #{@tempdir}/file[[:digit:]].txt > #{output_file}")
    content = File.read(output_file)
    assert_match(/file1\.txt/, content)
    assert_match(/file2\.txt/, content)
    assert_match(/file3\.txt/, content)
  end

  # Test no match returns pattern
  def test_posix_no_match_returns_pattern
    matches = @repl.send(:__glob, File.join(@tempdir, 'xyz[[:digit:]].txt'))
    assert_equal 1, matches.length
    assert matches.first.include?('[[:digit:]]')
  end
end
