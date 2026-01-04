# frozen_string_literal: true

require_relative 'test_helper'

class TestExtglob < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_extglob_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)

    # Enable extglob
    Rubish::Builtins.shell_options['extglob'] = true

    # Create test files
    File.write('file.txt', '')
    File.write('file.md', '')
    File.write('file.rb', '')
    File.write('file.py', '')
    File.write('test.txt', '')
    File.write('test.rb', '')
    File.write('foo.txt', '')
    File.write('bar.txt', '')
    File.write('baz.txt', '')
    File.write('file1.txt', '')
    File.write('file2.txt', '')
    File.write('file12.txt', '')
    File.write('image.jpg', '')
    File.write('image.png', '')
    File.write('image.gif', '')
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.shell_options['extglob'] = false
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Unit tests for helper methods
  def test_has_extglob_detects_question_pattern
    assert @repl.send(:has_extglob?, '?(foo)')
    assert @repl.send(:has_extglob?, 'file.?(txt|md)')
  end

  def test_has_extglob_detects_star_pattern
    assert @repl.send(:has_extglob?, '*(foo)')
    assert @repl.send(:has_extglob?, '*.*(txt|md)')
  end

  def test_has_extglob_detects_plus_pattern
    assert @repl.send(:has_extglob?, '+(foo)')
    assert @repl.send(:has_extglob?, 'file+(1|2).txt')
  end

  def test_has_extglob_detects_at_pattern
    assert @repl.send(:has_extglob?, '@(foo)')
    assert @repl.send(:has_extglob?, '@(foo|bar).txt')
  end

  def test_has_extglob_detects_exclamation_pattern
    assert @repl.send(:has_extglob?, '!(foo)')
    assert @repl.send(:has_extglob?, '!(*.txt)')
  end

  def test_has_extglob_false_for_regular_globs
    assert_false @repl.send(:has_extglob?, '*.txt')
    assert_false @repl.send(:has_extglob?, 'file?.txt')
    assert_false @repl.send(:has_extglob?, '[abc].txt')
  end

  # @(pattern|pattern) - exactly one
  def test_at_pattern_matches_alternatives
    result = @repl.send(:expand_extglob, '@(foo|bar).txt')
    assert_include result, 'bar.txt'
    assert_include result, 'foo.txt'
    assert_not_include result, 'baz.txt'
  end

  def test_at_pattern_matches_extensions
    result = @repl.send(:expand_extglob, 'file.@(txt|md)')
    assert_include result, 'file.txt'
    assert_include result, 'file.md'
    assert_not_include result, 'file.rb'
  end

  # ?(pattern|pattern) - zero or one
  def test_question_pattern_matches_zero_or_one
    result = @repl.send(:expand_extglob, 'file?(1|2).txt')
    assert_include result, 'file.txt'
    assert_include result, 'file1.txt'
    assert_include result, 'file2.txt'
    assert_not_include result, 'file12.txt'
  end

  # *(pattern|pattern) - zero or more
  def test_star_pattern_matches_zero_or_more
    result = @repl.send(:expand_extglob, 'file*(1|2).txt')
    assert_include result, 'file.txt'
    assert_include result, 'file1.txt'
    assert_include result, 'file2.txt'
    assert_include result, 'file12.txt'
  end

  # +(pattern|pattern) - one or more
  def test_plus_pattern_matches_one_or_more
    result = @repl.send(:expand_extglob, 'file+(1|2).txt')
    assert_not_include result, 'file.txt'
    assert_include result, 'file1.txt'
    assert_include result, 'file2.txt'
    assert_include result, 'file12.txt'
  end

  # !(pattern) - anything except
  def test_exclamation_pattern_excludes
    result = @repl.send(:expand_extglob, '!(*.txt)')
    assert_include result, 'file.md'
    assert_include result, 'file.rb'
    assert_include result, 'image.jpg'
    assert_not_include result, 'file.txt'
    assert_not_include result, 'test.txt'
  end

  # Extglob disabled
  def test_extglob_disabled_returns_literal
    Rubish::Builtins.shell_options['extglob'] = false
    result = @repl.send(:__glob, '@(foo|bar).txt')
    # When extglob is disabled, pattern is treated literally (no match)
    assert_equal ['@(foo|bar).txt'], result
  end

  # extglob_to_regex tests
  def test_extglob_to_regex_at_pattern
    regex = @repl.send(:extglob_to_regex, '@(foo|bar).txt')
    assert regex.match?('foo.txt')
    assert regex.match?('bar.txt')
    assert_false regex.match?('baz.txt')
  end

  def test_extglob_to_regex_question_pattern
    regex = @repl.send(:extglob_to_regex, 'file?(1).txt')
    assert regex.match?('file.txt')
    assert regex.match?('file1.txt')
    assert_false regex.match?('file11.txt')
  end

  def test_extglob_to_regex_star_pattern
    regex = @repl.send(:extglob_to_regex, 'file*(ab).txt')
    assert regex.match?('file.txt')
    assert regex.match?('fileab.txt')
    assert regex.match?('fileabab.txt')
  end

  def test_extglob_to_regex_plus_pattern
    regex = @repl.send(:extglob_to_regex, 'file+(ab).txt')
    assert_false regex.match?('file.txt')
    assert regex.match?('fileab.txt')
    assert regex.match?('fileabab.txt')
  end

  def test_extglob_to_regex_with_wildcards_inside
    regex = @repl.send(:extglob_to_regex, '@(*.txt|*.md)')
    assert regex.match?('file.txt')
    assert regex.match?('test.md')
    assert_false regex.match?('file.rb')
  end

  # Execution tests
  def test_glob_with_at_pattern
    result = @repl.send(:__glob, '@(foo|bar).txt')
    assert_include result, 'bar.txt'
    assert_include result, 'foo.txt'
    assert_equal 2, result.length
  end

  # Split alternatives tests
  def test_split_extglob_alternatives_simple
    result = @repl.send(:split_extglob_alternatives, 'foo|bar|baz')
    assert_equal %w[foo bar baz], result
  end

  def test_split_extglob_alternatives_nested
    result = @repl.send(:split_extglob_alternatives, 'foo|bar(1|2)|baz')
    assert_equal ['foo', 'bar(1|2)', 'baz'], result
  end

  # Image file matching
  def test_match_image_extensions
    result = @repl.send(:expand_extglob, '*.@(jpg|png|gif)')
    assert_include result, 'image.jpg'
    assert_include result, 'image.png'
    assert_include result, 'image.gif'
    assert_equal 3, result.length
  end

  # Non-txt files
  def test_exclude_txt_files
    result = @repl.send(:expand_extglob, '*.!(txt)')
    assert_include result, 'file.md'
    assert_include result, 'file.rb'
    assert_include result, 'file.py'
    assert_not_include result, 'file.txt'
    assert_not_include result, 'test.txt'
  end
end
