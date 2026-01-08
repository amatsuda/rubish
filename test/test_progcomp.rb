# frozen_string_literal: true

require_relative 'test_helper'

class TestProgcomp < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_progcomp_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    Rubish::Builtins.clear_completions
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    Rubish::Builtins.clear_completions
    FileUtils.rm_rf(@tempdir)
  end

  # progcomp is enabled by default
  def test_progcomp_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('progcomp')
  end

  def test_progcomp_can_be_disabled
    execute('shopt -u progcomp')
    assert_false Rubish::Builtins.shopt_enabled?('progcomp')
  end

  def test_progcomp_can_be_enabled
    execute('shopt -u progcomp')
    execute('shopt -s progcomp')
    assert Rubish::Builtins.shopt_enabled?('progcomp')
  end

  # Test that the complete method exists and can be invoked
  def test_complete_method_exists
    assert @repl.respond_to?(:complete, true)
  end

  # Test the option is in SHELL_OPTIONS
  def test_progcomp_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('progcomp')
    # SHELL_OPTIONS stores [default_value, description] arrays
    assert_equal true, Rubish::Builtins::SHELL_OPTIONS['progcomp'][0] # default on
  end

  # Test toggle behavior
  def test_toggle_progcomp
    # Default: enabled
    assert Rubish::Builtins.shopt_enabled?('progcomp')

    # Disable
    execute('shopt -u progcomp')
    assert_false Rubish::Builtins.shopt_enabled?('progcomp')

    # Re-enable
    execute('shopt -s progcomp')
    assert Rubish::Builtins.shopt_enabled?('progcomp')

    # Disable again
    execute('shopt -u progcomp')
    assert_false Rubish::Builtins.shopt_enabled?('progcomp')

    # Re-enable again
    execute('shopt -s progcomp')
    assert Rubish::Builtins.shopt_enabled?('progcomp')
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt progcomp')
    end
    assert_match(/progcomp/, output)
    assert_match(/on/, output)

    execute('shopt -u progcomp')

    output = capture_output do
      execute('shopt progcomp')
    end
    assert_match(/progcomp/, output)
    assert_match(/off/, output)
  end

  # Test that the option is listed in shopt output
  def test_option_in_shopt_list
    output = capture_output do
      execute('shopt')
    end
    assert_match(/progcomp/, output)
  end

  # Test completion specs still work with get_completion_spec (independent of progcomp)
  def test_completion_spec_can_be_set
    execute('complete -W "apple banana cherry" testcmd')
    spec = Rubish::Builtins.get_completion_spec('testcmd')
    assert_not_nil spec
    assert_equal 'apple banana cherry', spec[:wordlist]
  end

  # Test that get_completion_spec returns nil for non-existent command
  def test_completion_spec_nil_for_unknown
    spec = Rubish::Builtins.get_completion_spec('unknown_command_xyz')
    assert_nil spec
  end

  # Test that completion spec is accessible regardless of progcomp setting
  # (the check happens at the completion logic level, not in get_completion_spec)
  def test_completion_spec_accessible_when_disabled
    execute('complete -W "foo bar baz" mycmd')

    # Disable progcomp
    execute('shopt -u progcomp')

    # The spec should still be retrievable (progcomp only affects whether it's used)
    spec = Rubish::Builtins.get_completion_spec('mycmd')
    assert_not_nil spec
    assert_equal 'foo bar baz', spec[:wordlist]
  end

  # Test that multiple completion specs can be set
  def test_multiple_completion_specs
    execute('complete -W "start stop restart" service1')
    execute('complete -W "create delete update" service2')
    execute('complete -d cdcmd')
    execute('complete -f filecmd')

    spec1 = Rubish::Builtins.get_completion_spec('service1')
    spec2 = Rubish::Builtins.get_completion_spec('service2')
    spec3 = Rubish::Builtins.get_completion_spec('cdcmd')
    spec4 = Rubish::Builtins.get_completion_spec('filecmd')

    assert_equal 'start stop restart', spec1[:wordlist]
    assert_equal 'create delete update', spec2[:wordlist]
    assert_includes spec3[:actions], :directory
    assert_includes spec4[:actions], :file
  end

  # Test that complete -r removes completion spec
  def test_completion_spec_removal
    execute('complete -W "a b c" removecmd')
    assert_not_nil Rubish::Builtins.get_completion_spec('removecmd')

    execute('complete -r removecmd')
    assert_nil Rubish::Builtins.get_completion_spec('removecmd')
  end

  # Test shopt -q for progcomp
  def test_shopt_q_progcomp
    # Default is enabled, so -q should return true (success)
    result = Rubish::Builtins.run('shopt', ['-q', 'progcomp'])
    assert result

    Rubish::Builtins.run('shopt', ['-u', 'progcomp'])
    result = Rubish::Builtins.run('shopt', ['-q', 'progcomp'])
    assert_false result
  end
end
