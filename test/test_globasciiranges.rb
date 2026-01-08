# frozen_string_literal: true

require_relative 'test_helper'

class TestGlobasciiranges < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_globasciiranges_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  def glob(pattern)
    @repl.send(:__glob, pattern)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # globasciiranges is enabled by default
  def test_globasciiranges_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('globasciiranges')
  end

  def test_globasciiranges_can_be_disabled
    execute('shopt -u globasciiranges')
    assert_false Rubish::Builtins.shopt_enabled?('globasciiranges')
  end

  def test_globasciiranges_can_be_enabled
    execute('shopt -u globasciiranges')
    execute('shopt -s globasciiranges')
    assert Rubish::Builtins.shopt_enabled?('globasciiranges')
  end

  # Test the option is in SHELL_OPTIONS
  def test_globasciiranges_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('globasciiranges')
    # SHELL_OPTIONS stores [default_value, description] arrays
    assert_equal true, Rubish::Builtins::SHELL_OPTIONS['globasciiranges'][0] # default on
  end

  # Test ASCII ranges with globasciiranges enabled (default)
  def test_ascii_range_lowercase_enabled
    # Create test files using different characters
    FileUtils.touch('file_a.txt')
    FileUtils.touch('file_b.txt')
    FileUtils.touch('file_c.txt')
    FileUtils.touch('file_d.txt')

    # With globasciiranges enabled, [a-c] should match a, b, c but not d
    matches = glob('file_[a-c].txt')
    assert_includes matches, 'file_a.txt'
    assert_includes matches, 'file_b.txt'
    assert_includes matches, 'file_c.txt'
    assert_not_includes matches, 'file_d.txt'
  end

  def test_ascii_range_excludes_outside_range
    FileUtils.touch('file_a.txt')
    FileUtils.touch('file_m.txt')
    FileUtils.touch('file_z.txt')

    # [a-c] should only match 'a'
    matches = glob('file_[a-c].txt')
    assert_includes matches, 'file_a.txt'
    assert_not_includes matches, 'file_m.txt'
    assert_not_includes matches, 'file_z.txt'
  end

  # Test toggle behavior
  def test_toggle_globasciiranges
    FileUtils.touch('file_a.txt')
    FileUtils.touch('file_b.txt')

    # Default: enabled
    assert Rubish::Builtins.shopt_enabled?('globasciiranges')
    matches = glob('file_[a-b].txt')
    assert_equal 2, matches.length

    # Disable
    execute('shopt -u globasciiranges')
    assert_false Rubish::Builtins.shopt_enabled?('globasciiranges')

    # Re-enable
    execute('shopt -s globasciiranges')
    assert Rubish::Builtins.shopt_enabled?('globasciiranges')
  end

  # Test that non-letter ranges are not affected
  def test_numeric_range_not_affected
    FileUtils.touch('file_1.txt')
    FileUtils.touch('file_2.txt')
    FileUtils.touch('file_3.txt')
    FileUtils.touch('file_4.txt')

    # Numeric ranges should work the same regardless of globasciiranges
    matches = glob('file_[1-3].txt')
    assert_includes matches, 'file_1.txt'
    assert_includes matches, 'file_2.txt'
    assert_includes matches, 'file_3.txt'
    assert_not_includes matches, 'file_4.txt'

    execute('shopt -u globasciiranges')
    matches = glob('file_[1-3].txt')
    assert_includes matches, 'file_1.txt'
    assert_includes matches, 'file_2.txt'
    assert_includes matches, 'file_3.txt'
    assert_not_includes matches, 'file_4.txt'
  end

  # Test negated bracket expressions
  def test_negated_range
    FileUtils.touch('file_a.txt')
    FileUtils.touch('file_b.txt')
    FileUtils.touch('file_c.txt')

    # [!a-a] should NOT match 'a' but should match others
    matches = glob('file_[!a].txt')
    assert_not_includes matches, 'file_a.txt'
    assert_includes matches, 'file_b.txt'
    assert_includes matches, 'file_c.txt'
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt globasciiranges')
    end
    assert_match(/globasciiranges/, output)
    assert_match(/on/, output)

    execute('shopt -u globasciiranges')

    output = capture_output do
      execute('shopt globasciiranges')
    end
    assert_match(/globasciiranges/, output)
    assert_match(/off/, output)
  end

  # Test that the option is listed in shopt output
  def test_option_in_shopt_list
    output = capture_output do
      execute('shopt')
    end
    assert_match(/globasciiranges/, output)
  end

  # Test shopt -q for globasciiranges
  def test_shopt_q_globasciiranges
    # Default is enabled, so -q should return true
    result = Rubish::Builtins.run('shopt', ['-q', 'globasciiranges'])
    assert result

    Rubish::Builtins.run('shopt', ['-u', 'globasciiranges'])
    result = Rubish::Builtins.run('shopt', ['-q', 'globasciiranges'])
    assert_false result
  end

  # Test expand_locale_ranges helper method
  def test_expand_locale_ranges_method
    # Test lowercase range expansion
    result = @repl.send(:expand_locale_ranges, '[a-z]')
    assert_equal '[a-zA-Z]', result

    # Test uppercase range expansion
    result = @repl.send(:expand_locale_ranges, '[A-Z]')
    assert_equal '[A-Za-z]', result

    # Test mixed content
    result = @repl.send(:expand_locale_ranges, 'file_[a-c].txt')
    assert_equal 'file_[a-cA-C].txt', result

    # Test no brackets
    result = @repl.send(:expand_locale_ranges, 'file.txt')
    assert_equal 'file.txt', result

    # Test numeric range (should not expand)
    result = @repl.send(:expand_locale_ranges, '[0-9]')
    assert_equal '[0-9]', result

    # Test multiple brackets
    result = @repl.send(:expand_locale_ranges, '[a-b][x-y]')
    assert_equal '[a-bA-B][x-yX-Y]', result
  end

  # Test expand_bracket_ranges helper method
  def test_expand_bracket_ranges_method
    # Test lowercase range
    result = @repl.send(:expand_bracket_ranges, 'a-z')
    assert_equal 'a-zA-Z', result

    # Test uppercase range
    result = @repl.send(:expand_bracket_ranges, 'A-Z')
    assert_equal 'A-Za-z', result

    # Test partial range
    result = @repl.send(:expand_bracket_ranges, 'a-m')
    assert_equal 'a-mA-M', result

    # Test negation prefix
    result = @repl.send(:expand_bracket_ranges, '!a-z')
    assert_equal '!a-zA-Z', result

    # Test caret negation
    result = @repl.send(:expand_bracket_ranges, '^a-z')
    assert_equal '^a-zA-Z', result

    # Test no range (single characters)
    result = @repl.send(:expand_bracket_ranges, 'abc')
    assert_equal 'abc', result

    # Test mixed ranges and characters
    result = @repl.send(:expand_bracket_ranges, 'a-c123')
    assert_equal 'a-cA-C123', result
  end

  # Test pattern without brackets is unchanged
  def test_pattern_without_brackets_unchanged
    result = @repl.send(:expand_locale_ranges, 'file*.txt')
    assert_equal 'file*.txt', result

    result = @repl.send(:expand_locale_ranges, '**/*.rb')
    assert_equal '**/*.rb', result
  end

  # Test bracket without range is unchanged
  def test_bracket_without_range_unchanged
    result = @repl.send(:expand_locale_ranges, '[abc]')
    assert_equal '[abc]', result

    result = @repl.send(:expand_locale_ranges, '[!xyz]')
    assert_equal '[!xyz]', result
  end

  # Test that the expanded pattern works with Dir.glob
  def test_expanded_pattern_works_with_glob
    FileUtils.touch('test_a.txt')
    FileUtils.touch('test_b.txt')
    FileUtils.touch('test_1.txt')

    # Test that expanded pattern still works
    pattern = @repl.send(:expand_locale_ranges, 'test_[a-b].txt')
    matches = Dir.glob(pattern)
    assert_includes matches, 'test_a.txt'
    assert_includes matches, 'test_b.txt'
    assert_not_includes matches, 'test_1.txt'
  end

  # Test mixed letter and non-letter in bracket
  def test_mixed_letter_and_digit_range
    result = @repl.send(:expand_locale_ranges, '[a-z0-9]')
    # Only the letter range should be expanded
    assert_equal '[a-zA-Z0-9]', result
  end
end
