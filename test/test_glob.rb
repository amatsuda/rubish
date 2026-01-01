# frozen_string_literal: true

require_relative 'test_helper'

class TestGlob < Test::Unit::TestCase
  def setup
    @tempdir = Dir.mktmpdir('rubish_glob_test')
    # Create test files
    FileUtils.touch(File.join(@tempdir, 'file1.txt'))
    FileUtils.touch(File.join(@tempdir, 'file2.txt'))
    FileUtils.touch(File.join(@tempdir, 'file3.rb'))
    FileUtils.touch(File.join(@tempdir, 'data.json'))
    FileUtils.mkdir(File.join(@tempdir, 'subdir'))
    FileUtils.touch(File.join(@tempdir, 'subdir', 'nested.txt'))
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def test_star_glob
    cmd = Rubish::Command.new('echo', "#{@tempdir}/*.txt")
    args = cmd.args
    assert_equal 2, args.length
    assert_includes args, File.join(@tempdir, 'file1.txt')
    assert_includes args, File.join(@tempdir, 'file2.txt')
  end

  def test_question_mark_glob
    cmd = Rubish::Command.new('echo', "#{@tempdir}/file?.txt")
    args = cmd.args
    assert_equal 2, args.length
    assert_includes args, File.join(@tempdir, 'file1.txt')
    assert_includes args, File.join(@tempdir, 'file2.txt')
  end

  def test_bracket_glob
    cmd = Rubish::Command.new('echo', "#{@tempdir}/file[12].txt")
    args = cmd.args
    assert_equal 2, args.length
    assert_includes args, File.join(@tempdir, 'file1.txt')
    assert_includes args, File.join(@tempdir, 'file2.txt')
  end

  def test_double_star_glob
    cmd = Rubish::Command.new('echo', "#{@tempdir}/**/*.txt")
    args = cmd.args
    assert_equal 3, args.length
    assert_includes args, File.join(@tempdir, 'file1.txt')
    assert_includes args, File.join(@tempdir, 'file2.txt')
    assert_includes args, File.join(@tempdir, 'subdir', 'nested.txt')
  end

  def test_no_match_keeps_pattern
    cmd = Rubish::Command.new('echo', "#{@tempdir}/*.xyz")
    args = cmd.args
    assert_equal 1, args.length
    assert_equal "#{@tempdir}/*.xyz", args.first
  end

  def test_single_quoted_no_expansion
    cmd = Rubish::Command.new('echo', "'#{@tempdir}/*.txt'")
    args = cmd.args
    assert_equal 1, args.length
    assert_equal "#{@tempdir}/*.txt", args.first
  end

  def test_double_quoted_no_expansion
    cmd = Rubish::Command.new('echo', "\"#{@tempdir}/*.txt\"")
    args = cmd.args
    assert_equal 1, args.length
    assert_equal "#{@tempdir}/*.txt", args.first
  end

  def test_mixed_glob_and_regular_args
    cmd = Rubish::Command.new('echo', 'hello', "#{@tempdir}/*.txt", 'world')
    args = cmd.args
    assert_equal 4, args.length
    assert_equal 'hello', args.first
    assert_equal 'world', args.last
  end

  def test_glob_results_sorted
    cmd = Rubish::Command.new('echo', "#{@tempdir}/file*.txt")
    args = cmd.args
    assert_equal [File.join(@tempdir, 'file1.txt'), File.join(@tempdir, 'file2.txt')], args
  end

  def test_multiple_globs
    cmd = Rubish::Command.new('echo', "#{@tempdir}/*.txt", "#{@tempdir}/*.rb")
    args = cmd.args
    assert_equal 3, args.length
    assert_includes args, File.join(@tempdir, 'file1.txt')
    assert_includes args, File.join(@tempdir, 'file2.txt')
    assert_includes args, File.join(@tempdir, 'file3.rb')
  end

  def test_no_glob_chars_no_expansion
    cmd = Rubish::Command.new('echo', 'hello', 'world')
    args = cmd.args
    assert_equal ['hello', 'world'], args
  end

  def test_glob_with_extension_filter
    cmd = Rubish::Command.new('echo', "#{@tempdir}/*.{txt,rb}")
    args = cmd.args
    assert_equal 3, args.length
  end
end
