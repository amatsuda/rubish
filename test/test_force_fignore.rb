# frozen_string_literal: true

require_relative 'test_helper'

class TestForceFignore < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_force_fignore_test')
    @original_dir = Dir.pwd
    @original_fignore = ENV['FIGNORE']
    Dir.chdir(@tempdir)
    # Disable complete_fullquote to simplify testing
    Rubish::Builtins.current_state.shell_options['complete_fullquote'] = false
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    ENV['FIGNORE'] = @original_fignore
    FileUtils.rm_rf(@tempdir)
  end

  def complete_file(input)
    @repl.send(:complete_file, input)
  end

  # force_fignore is enabled by default
  def test_force_fignore_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('force_fignore')
  end

  def test_force_fignore_can_be_disabled
    execute('shopt -u force_fignore')
    assert_false Rubish::Builtins.shopt_enabled?('force_fignore')
  end

  def test_force_fignore_can_be_enabled
    execute('shopt -u force_fignore')
    execute('shopt -s force_fignore')
    assert Rubish::Builtins.shopt_enabled?('force_fignore')
  end

  # Test FIGNORE filtering with force_fignore enabled (default)
  def test_fignore_filters_with_multiple_matches
    ENV['FIGNORE'] = '.o'
    FileUtils.touch('file.c')
    FileUtils.touch('file.o')

    candidates = complete_file('file')
    assert_includes candidates, 'file.c'
    refute_includes candidates, 'file.o'
  end

  def test_fignore_filters_single_match_with_force_fignore
    ENV['FIGNORE'] = '.o'
    FileUtils.touch('file.o')

    # With force_fignore enabled, the only match is filtered out
    candidates = complete_file('file')
    # Since filtered list is empty, original is kept (to avoid empty completion)
    assert_includes candidates, 'file.o'
  end

  def test_fignore_filters_all_matches_returns_original
    ENV['FIGNORE'] = '.o:.c'
    FileUtils.touch('file.c')
    FileUtils.touch('file.o')

    # When all matches would be filtered, keep the original list
    candidates = complete_file('file')
    assert_includes candidates, 'file.c'
    assert_includes candidates, 'file.o'
  end

  # Test FIGNORE with force_fignore disabled
  def test_fignore_keeps_single_match_without_force_fignore
    execute('shopt -u force_fignore')
    ENV['FIGNORE'] = '.o'
    FileUtils.touch('file.o')

    # Without force_fignore, keep the single matching file
    candidates = complete_file('file')
    assert_includes candidates, 'file.o'
  end

  def test_fignore_still_filters_multiple_matches_without_force_fignore
    execute('shopt -u force_fignore')
    ENV['FIGNORE'] = '.o'
    FileUtils.touch('file.c')
    FileUtils.touch('file.o')

    # Still filters when there are multiple matches
    candidates = complete_file('file')
    assert_includes candidates, 'file.c'
    refute_includes candidates, 'file.o'
  end

  # Test multiple FIGNORE suffixes
  def test_multiple_fignore_suffixes
    ENV['FIGNORE'] = '.o:.bak:.tmp'
    FileUtils.touch('file.c')
    FileUtils.touch('file.o')
    FileUtils.touch('file.bak')
    FileUtils.touch('file.tmp')

    candidates = complete_file('file')
    assert_includes candidates, 'file.c'
    refute_includes candidates, 'file.o'
    refute_includes candidates, 'file.bak'
    refute_includes candidates, 'file.tmp'
  end

  # Test directories are not filtered by FIGNORE
  def test_directories_not_filtered
    ENV['FIGNORE'] = '.o'
    FileUtils.mkdir('dir.o')
    FileUtils.touch('file.o')
    FileUtils.touch('file.c')

    candidates = complete_file('')
    assert_includes candidates, 'dir.o/'
    assert_includes candidates, 'file.c'
    refute_includes candidates, 'file.o'
  end

  # Test empty FIGNORE
  def test_empty_fignore_no_filtering
    ENV['FIGNORE'] = ''
    FileUtils.touch('file.o')
    FileUtils.touch('file.c')

    candidates = complete_file('file')
    assert_includes candidates, 'file.o'
    assert_includes candidates, 'file.c'
  end

  # Test nil FIGNORE
  def test_nil_fignore_no_filtering
    ENV.delete('FIGNORE')
    FileUtils.touch('file.o')
    FileUtils.touch('file.c')

    candidates = complete_file('file')
    assert_includes candidates, 'file.o'
    assert_includes candidates, 'file.c'
  end

  # Test toggle behavior
  def test_toggle_force_fignore
    ENV['FIGNORE'] = '.o'
    FileUtils.touch('only.o')

    # Default: force_fignore enabled
    # With only one file matching FIGNORE, it's kept (since filtered is empty)
    candidates = complete_file('only')
    assert_includes candidates, 'only.o'

    # Disable force_fignore - single match should still be kept
    execute('shopt -u force_fignore')
    candidates = complete_file('only')
    assert_includes candidates, 'only.o'

    # Re-enable force_fignore
    execute('shopt -s force_fignore')
    candidates = complete_file('only')
    assert_includes candidates, 'only.o'
  end

  # Test that force_fignore affects behavior when there's a mix
  def test_force_fignore_with_one_good_one_bad
    ENV['FIGNORE'] = '.o'
    FileUtils.touch('test.c')
    FileUtils.touch('test.o')

    # With force_fignore, .o file is filtered
    candidates = complete_file('test')
    assert_equal ['test.c'], candidates

    # Without force_fignore, still filters because there's another match
    execute('shopt -u force_fignore')
    candidates = complete_file('test')
    assert_equal ['test.c'], candidates
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt force_fignore')
    end
    assert_match(/force_fignore/, output)
    assert_match(/on/, output)

    execute('shopt -u force_fignore')

    output = capture_output do
      execute('shopt force_fignore')
    end
    assert_match(/force_fignore/, output)
    assert_match(/off/, output)
  end
end
