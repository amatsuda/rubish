# frozen_string_literal: true

require_relative 'test_helper'

class TestAbbreviatedPathCompletion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_abbrev_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
  end

  def complete_file(input)
    @repl.send(:complete_file, input)
  end

  def expand_abbreviated_dir(input)
    @repl.send(:expand_abbreviated_dir, input)
  end

  def expand_abbreviated_path_for_completion(input)
    @repl.send(:expand_abbreviated_path_for_completion, input)
  end

  # ==========================================================================
  # expand_abbreviated_dir tests
  # ==========================================================================

  def test_expand_abbreviated_dir_single_level
    FileUtils.mkdir_p('library')
    assert_equal 'library', expand_abbreviated_dir('l')
  end

  def test_expand_abbreviated_dir_nested
    FileUtils.mkdir_p('library/rubish')
    assert_equal 'library/rubish', expand_abbreviated_dir('l/r')
  end

  def test_expand_abbreviated_dir_existing_dir
    FileUtils.mkdir_p('exact')
    assert_equal 'exact', expand_abbreviated_dir('exact')
  end

  def test_expand_abbreviated_dir_no_match
    FileUtils.mkdir_p('aaa')
    assert_nil expand_abbreviated_dir('xyz')
  end

  def test_expand_abbreviated_dir_dot
    assert_equal '.', expand_abbreviated_dir('.')
  end

  # ==========================================================================
  # expand_abbreviated_path_for_completion tests
  # ==========================================================================

  def test_expand_abbreviated_path_for_completion_file
    FileUtils.mkdir_p('library/rubish')
    FileUtils.touch('library/rubish/repl.rb')

    result = expand_abbreviated_path_for_completion('l/r/re')
    assert_equal ['l/r/repl.rb'], result
  end

  def test_expand_abbreviated_path_for_completion_multiple_files
    FileUtils.mkdir_p('library/rubish')
    FileUtils.touch('library/rubish/repl.rb')
    FileUtils.touch('library/rubish/runtime.rb')

    result = expand_abbreviated_path_for_completion('l/r/r')
    assert_include result, 'l/r/repl.rb'
    assert_include result, 'l/r/runtime.rb'
  end

  def test_expand_abbreviated_path_for_completion_directory
    FileUtils.mkdir_p('library/rubish/runtime')

    result = expand_abbreviated_path_for_completion('l/r/ru')
    assert_include result, 'l/r/runtime/'
  end

  def test_expand_abbreviated_path_for_completion_trailing_slash
    FileUtils.mkdir_p('library/rubish')
    FileUtils.touch('library/rubish/file1.rb')
    FileUtils.touch('library/rubish/file2.rb')

    result = expand_abbreviated_path_for_completion('l/r/')
    assert_include result, 'l/r/file1.rb'
    assert_include result, 'l/r/file2.rb'
  end

  # ==========================================================================
  # complete_file with abbreviated paths tests
  # ==========================================================================

  def test_complete_file_abbreviated_path
    FileUtils.mkdir_p('library/rubish')
    FileUtils.touch('library/rubish/repl.rb')

    candidates = complete_file('l/r/re')
    assert_equal ['l/r/repl.rb'], candidates
  end

  def test_complete_file_abbreviated_path_no_match
    FileUtils.mkdir_p('library/rubish')
    FileUtils.touch('library/rubish/repl.rb')

    candidates = complete_file('x/y/z')
    assert_empty candidates
  end

  def test_complete_file_abbreviated_results_start_with_input
    FileUtils.mkdir_p('library/rubish')
    FileUtils.touch('library/rubish/repl.rb')

    candidates = complete_file('l/r/re')
    candidates.each do |c|
      assert c.start_with?('l/r/re'), "Expected '#{c}' to start with 'l/r/re'"
    end
  end

  def test_complete_file_prefers_exact_match_over_abbreviated
    FileUtils.mkdir_p('l/r')
    FileUtils.touch('l/r/re.txt')
    FileUtils.mkdir_p('library/rubish')
    FileUtils.touch('library/rubish/repl.rb')

    # When exact path exists, use it
    candidates = complete_file('l/r/re')
    assert_include candidates, 'l/r/re.txt'
  end
end
