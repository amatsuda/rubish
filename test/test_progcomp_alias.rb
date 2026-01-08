# frozen_string_literal: true

require_relative 'test_helper'

class TestProgcompAlias < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_aliases = Rubish::Builtins.aliases.dup
    @original_completions = Rubish::Builtins.instance_variable_get(:@completions).dup
    @tempdir = Dir.mktmpdir('rubish_progcomp_alias_test')
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    Rubish::Builtins.aliases.clear
    @original_aliases.each { |k, v| Rubish::Builtins.aliases[k] = v }
    completions = Rubish::Builtins.instance_variable_get(:@completions)
    completions.clear
    @original_completions.each { |k, v| completions[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  # progcomp_alias is enabled by default
  def test_progcomp_alias_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('progcomp_alias')
  end

  def test_progcomp_alias_can_be_disabled
    execute('shopt -u progcomp_alias')
    assert_false Rubish::Builtins.shopt_enabled?('progcomp_alias')
  end

  def test_progcomp_alias_can_be_re_enabled
    execute('shopt -u progcomp_alias')
    execute('shopt -s progcomp_alias')
    assert Rubish::Builtins.shopt_enabled?('progcomp_alias')
  end

  # Test get_completion_spec behavior without progcomp_alias
  def test_get_completion_spec_returns_nil_for_alias_without_option
    # Disable progcomp_alias first
    execute('shopt -u progcomp_alias')

    # Define an alias
    execute("alias myalias='git'")

    # Define a completion spec for git
    execute("complete -W 'status commit push pull' git")

    # Without progcomp_alias, alias should not get git's completion
    spec = Rubish::Builtins.get_completion_spec('myalias')
    assert_nil spec
  end

  # Test get_completion_spec behavior with progcomp_alias
  def test_get_completion_spec_returns_aliased_command_spec

    # Define an alias
    execute("alias g='git'")

    # Define a completion spec for git
    execute("complete -W 'status commit push pull' git")

    # With progcomp_alias, alias should get git's completion
    spec = Rubish::Builtins.get_completion_spec('g')
    assert_not_nil spec
    assert_match(/status/, spec[:wordlist])
    assert_match(/commit/, spec[:wordlist])
  end

  # Test with alias that has arguments
  def test_get_completion_spec_with_alias_with_args
    execute('shopt -s progcomp_alias')

    # Define an alias with arguments
    execute("alias gs='git status'")

    # Define a completion spec for git
    execute("complete -W 'status commit push pull' git")

    # Should still get git's completion (first word of alias)
    spec = Rubish::Builtins.get_completion_spec('gs')
    assert_not_nil spec
    assert_match(/status/, spec[:wordlist])
  end

  # Test that direct completion spec takes precedence
  def test_direct_completion_spec_takes_precedence
    execute('shopt -s progcomp_alias')

    # Define an alias
    execute("alias myalias='git'")

    # Define completion specs for both
    execute("complete -W 'status commit push pull' git")
    execute("complete -W 'custom1 custom2' myalias")

    # Direct spec should take precedence
    spec = Rubish::Builtins.get_completion_spec('myalias')
    assert_not_nil spec
    assert_match(/custom1/, spec[:wordlist])
    assert_match(/custom2/, spec[:wordlist])
    refute_match(/status/, spec[:wordlist])
  end

  # Test with non-existent alias target
  def test_get_completion_spec_with_no_target_spec
    execute('shopt -s progcomp_alias')

    # Define an alias to a command without completion
    execute("alias myalias='nonexistent_cmd'")

    # Should return nil since nonexistent_cmd has no completion
    spec = Rubish::Builtins.get_completion_spec('myalias')
    assert_nil spec
  end

  # Test that non-alias returns nil
  def test_get_completion_spec_for_non_alias
    execute('shopt -s progcomp_alias')

    # No alias defined, no completion defined
    spec = Rubish::Builtins.get_completion_spec('not_an_alias')
    assert_nil spec
  end

  # Test self-referencing alias doesn't cause infinite loop
  def test_self_referencing_alias
    execute('shopt -s progcomp_alias')

    # Define an alias that points to itself
    execute("alias foo='foo --bar'")

    # Should return nil (avoid infinite loop)
    spec = Rubish::Builtins.get_completion_spec('foo')
    assert_nil spec
  end

  # Test disabling restores default behavior
  def test_disable_restores_default_behavior
    execute('shopt -s progcomp_alias')

    # Define an alias
    execute("alias g='git'")
    execute("complete -W 'status commit' git")

    # Should find spec
    spec = Rubish::Builtins.get_completion_spec('g')
    assert_not_nil spec

    # Disable progcomp_alias
    execute('shopt -u progcomp_alias')

    # Should not find spec anymore
    spec = Rubish::Builtins.get_completion_spec('g')
    assert_nil spec
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt progcomp_alias')
    end
    assert_match(/progcomp_alias/, output)
    assert_match(/on/, output)  # enabled by default

    execute('shopt -u progcomp_alias')

    output = capture_output do
      execute('shopt progcomp_alias')
    end
    assert_match(/progcomp_alias/, output)
    assert_match(/off/, output)
  end
end
