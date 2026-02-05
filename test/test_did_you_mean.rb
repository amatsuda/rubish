# frozen_string_literal: true

require_relative 'test_helper'

class TestDidYouMean < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_dym_test')
    # Clear the command cache before each test
    Rubish::Command.clear_command_cache
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    Rubish::Command.clear_command_cache
  end

  # Test available_commands returns an array of command names
  def test_available_commands_returns_array
    commands = Rubish::Command.available_commands
    assert_kind_of Array, commands
    assert commands.length > 0, 'Should find at least some commands in PATH'
  end

  # Test available_commands contains common commands
  def test_available_commands_contains_common_commands
    commands = Rubish::Command.available_commands
    # These commands should exist on any Unix system
    assert commands.include?('ls'), 'Should include ls'
    assert commands.include?('cat'), 'Should include cat'
    assert commands.include?('echo'), 'Should include echo'
  end

  # Test suggest_similar_commands returns suggestions for typos
  def test_suggest_similar_commands_for_typo
    suggestions = Rubish::Command.suggest_similar_commands('lss')
    assert_kind_of Array, suggestions
    assert suggestions.include?('ls'), "Should suggest 'ls' for 'lss'"
  end

  # Test suggest_similar_commands for another typo
  def test_suggest_similar_commands_for_mkdir_typo
    suggestions = Rubish::Command.suggest_similar_commands('mkidr')
    assert_kind_of Array, suggestions
    assert suggestions.include?('mkdir'), "Should suggest 'mkdir' for 'mkidr'"
  end

  # Test suggest_similar_commands returns empty array for completely unknown
  def test_suggest_similar_commands_no_match
    suggestions = Rubish::Command.suggest_similar_commands('zzzxyznonexistent')
    assert_kind_of Array, suggestions
    assert suggestions.empty?, 'Should return empty array for completely unknown command'
  end

  # Test clear_command_cache clears the cache
  def test_clear_command_cache
    # Populate the cache
    Rubish::Command.available_commands
    # Clear it
    Rubish::Command.clear_command_cache
    # Access the instance variable directly to verify it's nil
    cache = Rubish::Command.instance_variable_get(:@available_commands_cache)
    assert_nil cache, 'Cache should be nil after clearing'
  end

  # Test command not found error includes suggestions
  def test_command_not_found_shows_suggestions
    error_file = File.join(@tempdir, 'stderr.txt')
    execute("lss 2>#{error_file}")
    error_output = File.read(error_file)

    assert_match(/command not found/, error_output)
    assert_match(/Did you mean\?/, error_output)
    assert_match(/ls/, error_output)
  end

  # Test command not found error without suggestions for unknown command
  def test_command_not_found_no_suggestions_for_unknown
    error_file = File.join(@tempdir, 'stderr.txt')
    execute("zzzxyznonexistent 2>#{error_file}")
    error_output = File.read(error_file)

    assert_match(/command not found/, error_output)
    assert_no_match(/Did you mean\?/, error_output)
  end

  # Test exit status is 127 for command not found
  def test_command_not_found_exit_status
    execute('nonexistent_cmd_xyz')
    assert_equal 127, @repl.instance_variable_get(:@last_status)
  end
end
