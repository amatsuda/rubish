# frozen_string_literal: true

require_relative 'test_helper'

class TestShoptNew < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_shopt_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test that all new options exist and can be enabled/disabled

  def test_checkwinsize_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('checkwinsize')
    assert_false Rubish::Builtins.shopt_enabled?('checkwinsize')
    execute('shopt -s checkwinsize')
    assert Rubish::Builtins.shopt_enabled?('checkwinsize')
    execute('shopt -u checkwinsize')
    assert_false Rubish::Builtins.shopt_enabled?('checkwinsize')
  end

  def test_direxpand_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('direxpand')
    assert_false Rubish::Builtins.shopt_enabled?('direxpand')
    execute('shopt -s direxpand')
    assert Rubish::Builtins.shopt_enabled?('direxpand')
  end

  def test_dirspell_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('dirspell')
    assert_false Rubish::Builtins.shopt_enabled?('dirspell')
    execute('shopt -s dirspell')
    assert Rubish::Builtins.shopt_enabled?('dirspell')
  end

  def test_execfail_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('execfail')
    assert_false Rubish::Builtins.shopt_enabled?('execfail')
    execute('shopt -s execfail')
    assert Rubish::Builtins.shopt_enabled?('execfail')
  end

  def test_extquote_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('extquote')
    # extquote is enabled by default
    assert Rubish::Builtins.shopt_enabled?('extquote')
    execute('shopt -u extquote')
    assert_false Rubish::Builtins.shopt_enabled?('extquote')
  end

  def test_failglob_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('failglob')
    assert_false Rubish::Builtins.shopt_enabled?('failglob')
    execute('shopt -s failglob')
    assert Rubish::Builtins.shopt_enabled?('failglob')
  end

  def test_globskipdots_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('globskipdots')
    assert_false Rubish::Builtins.shopt_enabled?('globskipdots')
    execute('shopt -s globskipdots')
    assert Rubish::Builtins.shopt_enabled?('globskipdots')
  end

  def test_huponexit_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('huponexit')
    assert_false Rubish::Builtins.shopt_enabled?('huponexit')
    execute('shopt -s huponexit')
    assert Rubish::Builtins.shopt_enabled?('huponexit')
  end

  def test_inherit_errexit_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('inherit_errexit')
    assert_false Rubish::Builtins.shopt_enabled?('inherit_errexit')
    execute('shopt -s inherit_errexit')
    assert Rubish::Builtins.shopt_enabled?('inherit_errexit')
  end

  def test_lastpipe_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('lastpipe')
    assert_false Rubish::Builtins.shopt_enabled?('lastpipe')
    execute('shopt -s lastpipe')
    assert Rubish::Builtins.shopt_enabled?('lastpipe')
  end

  def test_shift_verbose_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('shift_verbose')
    assert_false Rubish::Builtins.shopt_enabled?('shift_verbose')
    execute('shopt -s shift_verbose')
    assert Rubish::Builtins.shopt_enabled?('shift_verbose')
  end

  # Behavioral tests for shift_verbose

  def test_shift_verbose_disabled_no_error_message
    @repl.positional_params = ['a', 'b']
    stderr = capture_stderr do
      execute('shift 5')
    end
    assert_equal '', stderr
  end

  def test_shift_verbose_enabled_prints_error
    execute('shopt -s shift_verbose')
    @repl.positional_params = ['a', 'b']
    stderr = capture_stderr do
      execute('shift 5')
    end
    assert_match(/shift count out of range/, stderr)
  end

  def test_shift_verbose_no_error_when_within_range
    execute('shopt -s shift_verbose')
    @repl.positional_params = ['a', 'b', 'c']
    stderr = capture_stderr do
      execute('shift 2')
    end
    assert_equal '', stderr
    assert_equal ['c'], @repl.positional_params
  end

  # Behavioral tests for globskipdots

  def test_globskipdots_filters_dot_and_dotdot
    # Create some dotfiles for testing
    FileUtils.touch('.hidden')
    FileUtils.touch('.other')
    FileUtils.touch('regular')

    # Enable dotglob to match dotfiles, but not globskipdots
    execute('shopt -s dotglob')
    execute('shopt -u globskipdots')

    # Glob should include . and .. without globskipdots
    matches = @repl.send(:__glob, '*')
    # Actually, Dir.glob doesn't include . and .. by default
    # The . and .. filtering is for when patterns like .* are used

    # Let's test with .* pattern
    matches = @repl.send(:__glob, '.*')
    # With dotglob enabled, the filter already removes . and ..
    refute_includes matches, '.'
    refute_includes matches, '..'

    # Now let's test without dotglob but with globskipdots
    execute('shopt -u dotglob')
    execute('shopt -s globskipdots')

    # Match dotfiles with .*
    matches = @repl.send(:__glob, '.*')
    refute_includes matches, '.'
    refute_includes matches, '..'
    assert_includes matches, '.hidden'
    assert_includes matches, '.other'
  end

  def test_globskipdots_with_subdirectory
    # Create a subdirectory with dotfiles
    FileUtils.mkdir_p('subdir')
    FileUtils.touch('subdir/.hidden')

    execute('shopt -s dotglob')
    execute('shopt -s globskipdots')

    matches = @repl.send(:__glob, 'subdir/.*')
    refute matches.any? { |m| m.end_with?('/.') }
    refute matches.any? { |m| m.end_with?('/..') }
  end

  # Test that options appear in RUBISHOPTS when enabled

  def test_new_options_in_rubishopts
    execute('shopt -s checkwinsize')
    execute('shopt -s globskipdots')
    execute('shopt -s shift_verbose')

    result = Rubish::Builtins.rubishopts
    assert_includes result.split(':'), 'checkwinsize'
    assert_includes result.split(':'), 'globskipdots'
    assert_includes result.split(':'), 'shift_verbose'
  end
end
