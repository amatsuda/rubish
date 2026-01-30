# frozen_string_literal: true

require_relative 'test_helper'

class TestCompopt < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @saved_stderr = $stderr
    @saved_stdout = $stdout
    # Save and clear completion options
    @original_completion_options = Rubish::Builtins.current_state.completion_options.dup
    @original_current_completion_options = Rubish::Builtins.current_state.current_completion_options.dup
    Rubish::Builtins.current_state.completion_options.clear
    Rubish::Builtins.current_state.current_completion_options = Set.new
  end

  def teardown
    $stderr = @saved_stderr
    $stdout = @saved_stdout
    Rubish::Builtins.current_state.completion_options.clear
    @original_completion_options.each { |k, v| Rubish::Builtins.current_state.completion_options[k] = v }
    Rubish::Builtins.current_state.current_completion_options = @original_current_completion_options
  end

  # Basic tests
  def test_compopt_is_builtin
    assert Rubish::Builtins.builtin?('compopt')
  end

  def test_compopt_in_commands_list
    assert_include Rubish::Builtins::COMMANDS, 'compopt'
  end

  # Enable options with -o
  def test_compopt_enable_option_for_command
    result = Rubish::Builtins.compopt(['-o', 'nospace', 'git'])
    assert_true result
    assert Rubish::Builtins.completion_option?('git', 'nospace')
  end

  def test_compopt_enable_multiple_options
    Rubish::Builtins.compopt(['-o', 'nospace', '-o', 'filenames', 'git'])
    assert Rubish::Builtins.completion_option?('git', 'nospace')
    assert Rubish::Builtins.completion_option?('git', 'filenames')
  end

  def test_compopt_enable_option_for_multiple_commands
    Rubish::Builtins.compopt(['-o', 'nospace', 'git', 'svn', 'hg'])
    assert Rubish::Builtins.completion_option?('git', 'nospace')
    assert Rubish::Builtins.completion_option?('svn', 'nospace')
    assert Rubish::Builtins.completion_option?('hg', 'nospace')
  end

  # Disable options with +o
  def test_compopt_disable_option
    Rubish::Builtins.compopt(['-o', 'nospace', 'git'])
    assert Rubish::Builtins.completion_option?('git', 'nospace')

    Rubish::Builtins.compopt(['+o', 'nospace', 'git'])
    assert_false Rubish::Builtins.completion_option?('git', 'nospace')
  end

  def test_compopt_disable_nonexistent_option
    # Should not error when disabling option that isn't set
    result = Rubish::Builtins.compopt(['+o', 'nospace', 'git'])
    assert_true result
  end

  # Combined form -oOPTION
  def test_compopt_combined_enable_form
    result = Rubish::Builtins.compopt(['-onospace', 'git'])
    assert_true result
    assert Rubish::Builtins.completion_option?('git', 'nospace')
  end

  def test_compopt_combined_disable_form
    Rubish::Builtins.compopt(['-o', 'nospace', 'git'])
    Rubish::Builtins.compopt(['+onospace', 'git'])
    assert_false Rubish::Builtins.completion_option?('git', 'nospace')
  end

  # Current completion options (no command name)
  def test_compopt_current_completion_enable
    Rubish::Builtins.compopt(['-o', 'nospace'])
    assert_include Rubish::Builtins.current_state.current_completion_options, 'nospace'
  end

  def test_compopt_current_completion_disable
    Rubish::Builtins.current_state.current_completion_options = Set.new(['nospace'])
    Rubish::Builtins.compopt(['+o', 'nospace'])
    assert_not_include Rubish::Builtins.current_state.current_completion_options, 'nospace'
  end

  # -D default completion
  def test_compopt_default_completion
    Rubish::Builtins.compopt(['-o', 'dirnames', '-D'])
    assert Rubish::Builtins.completion_option?(:default, 'dirnames')
  end

  def test_compopt_default_completion_disable
    Rubish::Builtins.compopt(['-o', 'dirnames', '-D'])
    Rubish::Builtins.compopt(['+o', 'dirnames', '-D'])
    assert_false Rubish::Builtins.completion_option?(:default, 'dirnames')
  end

  # -E empty command completion
  def test_compopt_empty_completion
    Rubish::Builtins.compopt(['-o', 'bashdefault', '-E'])
    assert Rubish::Builtins.completion_option?(:empty, 'bashdefault')
  end

  def test_compopt_empty_completion_disable
    Rubish::Builtins.compopt(['-o', 'bashdefault', '-E'])
    Rubish::Builtins.compopt(['+o', 'bashdefault', '-E'])
    assert_false Rubish::Builtins.completion_option?(:empty, 'bashdefault')
  end

  # Invalid option handling
  def test_compopt_invalid_option_returns_false
    $stderr = StringIO.new
    result = Rubish::Builtins.compopt(['-o', 'invalid_option', 'git'])
    assert_false result
  end

  def test_compopt_invalid_option_prints_error
    output = capture_stderr do
      Rubish::Builtins.compopt(['-o', 'badopt', 'git'])
    end
    assert_match(/badopt: invalid option name/, output)
  end

  def test_compopt_invalid_disable_option_returns_false
    $stderr = StringIO.new
    result = Rubish::Builtins.compopt(['+o', 'invalid', 'git'])
    assert_false result
  end

  # All valid options
  def test_compopt_all_valid_options
    valid_options = %w[bashdefault default dirnames filenames noquote nosort nospace plusdirs]
    valid_options.each do |opt|
      result = Rubish::Builtins.compopt(['-o', opt, 'testcmd'])
      assert_true result, "Option #{opt} should be valid"
      assert Rubish::Builtins.completion_option?('testcmd', opt)
    end
  end

  # Print options (no -o/+o specified)
  def test_compopt_print_current_options_empty
    output = capture_stdout do
      Rubish::Builtins.compopt([])
    end
    assert_match(/no options set/, output)
  end

  def test_compopt_print_current_options
    Rubish::Builtins.current_state.current_completion_options = Set.new(['nospace', 'filenames'])
    output = capture_stdout do
      Rubish::Builtins.compopt([])
    end
    assert_match(/compopt -o nospace/, output)
    assert_match(/compopt -o filenames/, output)
  end

  def test_compopt_print_command_options_empty
    output = capture_stdout do
      Rubish::Builtins.compopt(['git'])
    end
    assert_match(/git: no options/, output)
  end

  def test_compopt_print_command_options
    Rubish::Builtins.compopt(['-o', 'nospace', '-o', 'dirnames', 'git'])
    output = capture_stdout do
      Rubish::Builtins.compopt(['git'])
    end
    assert_match(/compopt -o nospace git/, output)
    assert_match(/compopt -o dirnames git/, output)
  end

  def test_compopt_print_default_options
    Rubish::Builtins.compopt(['-o', 'filenames', '-D'])
    output = capture_stdout do
      Rubish::Builtins.compopt(['-D'])
    end
    assert_match(/compopt -o filenames -D/, output)
  end

  # Helper method tests
  def test_get_completion_options_empty
    opts = Rubish::Builtins.get_completion_options('nonexistent')
    assert_instance_of Set, opts
    assert opts.empty?
  end

  def test_get_completion_options
    Rubish::Builtins.compopt(['-o', 'nospace', '-o', 'filenames', 'git'])
    opts = Rubish::Builtins.get_completion_options('git')
    assert_include opts, 'nospace'
    assert_include opts, 'filenames'
  end

  def test_completion_option_predicate
    Rubish::Builtins.compopt(['-o', 'nospace', 'git'])
    assert_true Rubish::Builtins.completion_option?('git', 'nospace')
    assert_false Rubish::Builtins.completion_option?('git', 'filenames')
  end

  # Combined -D and -E with commands
  def test_compopt_combined_default_empty_and_commands
    Rubish::Builtins.compopt(['-o', 'nospace', '-D', '-E', 'git', 'svn'])
    assert Rubish::Builtins.completion_option?(:default, 'nospace')
    assert Rubish::Builtins.completion_option?(:empty, 'nospace')
    assert Rubish::Builtins.completion_option?('git', 'nospace')
    assert Rubish::Builtins.completion_option?('svn', 'nospace')
  end

  # COMPLETION_OPTIONS constant
  def test_completion_options_constant_exists
    assert_kind_of Array, Rubish::Builtins::COMPLETION_OPTIONS
    assert_include Rubish::Builtins::COMPLETION_OPTIONS, 'nospace'
    assert_include Rubish::Builtins::COMPLETION_OPTIONS, 'filenames'
    assert_include Rubish::Builtins::COMPLETION_OPTIONS, 'dirnames'
  end
end
