# frozen_string_literal: true

require_relative 'test_helper'

class TestTildeCompletion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
  end

  def complete_file(input)
    @repl.send(:complete_file, input)
  end

  # Test get_system_users helper
  def test_get_system_users_returns_current_user
    users = Rubish::Builtins.get_system_users
    current_user = ENV['USER'] || ENV['LOGNAME']
    assert_includes users, current_user if current_user
  end

  def test_get_system_users_filters_system_accounts
    users = Rubish::Builtins.get_system_users
    # System accounts starting with _ should be filtered out
    system_users = users.select { |u| u.start_with?('_') }
    assert_empty system_users, 'System accounts should be filtered out'
  end

  def test_get_system_users_returns_sorted_list
    users = Rubish::Builtins.get_system_users
    assert_equal users.sort, users
  end

  # Test username completion via run__filedir
  def test_username_completion_shows_tilde_slash_first
    Rubish::Builtins.call_builtin_completion_function('_cd', 'cd', '~', '')
    result = Rubish::Builtins.compreply
    assert_equal '~/', result.first, '~/ should be first in completion list'
  end

  def test_username_completion_includes_current_user
    current_user = ENV['USER'] || ENV['LOGNAME']
    return unless current_user

    Rubish::Builtins.call_builtin_completion_function('_cd', 'cd', '~', '')
    result = Rubish::Builtins.compreply
    assert_includes result, "~#{current_user}/"
  end

  def test_username_completion_filters_by_prefix
    current_user = ENV['USER'] || ENV['LOGNAME']
    return unless current_user

    prefix = current_user[0, 2]
    Rubish::Builtins.instance_variable_set(:@compreply, [])
    Rubish::Builtins.call_builtin_completion_function('_cd', 'cd', "~#{prefix}", '')
    result = Rubish::Builtins.compreply

    # All results should start with the prefix
    result.each do |r|
      assert r.start_with?("~#{prefix}"), "#{r} should start with ~#{prefix}"
    end
  end

  def test_username_completion_no_error_for_invalid_user
    # Should not raise an error
    Rubish::Builtins.instance_variable_set(:@compreply, [])
    Rubish::Builtins.call_builtin_completion_function('_cd', 'cd', '~nonexistentuser12345', '')
    result = Rubish::Builtins.compreply
    assert_equal [], result
  end

  # Test ~/ file completion via complete_file
  def test_complete_file_with_tilde_slash
    test_subdir = File.join(Dir.home, 'rubish_tilde_test_temp')
    FileUtils.mkdir_p(test_subdir)

    begin
      candidates = complete_file('~/rubish_tilde_test')
      assert_includes candidates, '~/rubish_tilde_test_temp/'
    ensure
      FileUtils.rm_rf(test_subdir)
    end
  end

  def test_complete_file_with_tilde_slash_hidden_file
    test_subdir = File.join(Dir.home, '.rubish_tilde_test_hidden_temp')
    FileUtils.mkdir_p(test_subdir)

    begin
      # Hidden files require . prefix in input
      candidates = complete_file('~/.rubish_tilde_test_hidden')
      assert_includes candidates, '~/.rubish_tilde_test_hidden_temp/'
    ensure
      FileUtils.rm_rf(test_subdir)
    end
  end

  # Test ~/ completion via _cd_completion (cd command)
  def test_cd_completion_with_tilde_slash
    test_subdir = File.join(Dir.home, 'rubish_cd_tilde_test_temp')
    FileUtils.mkdir_p(test_subdir)

    begin
      Rubish::Builtins.instance_variable_set(:@compreply, [])
      Rubish::Builtins.call_builtin_completion_function('_cd', 'cd', '~/rubish_cd_tilde_test', '')
      result = Rubish::Builtins.compreply
      assert_includes result, '~/rubish_cd_tilde_test_temp/'
    ensure
      FileUtils.rm_rf(test_subdir)
    end
  end

  def test_cd_completion_with_tilde_slash_lists_home_contents
    Rubish::Builtins.instance_variable_set(:@compreply, [])
    Rubish::Builtins.call_builtin_completion_function('_cd', 'cd', '~/', '')
    result = Rubish::Builtins.compreply

    # Should have some results (home directory contents)
    assert !result.empty?, 'Should list home directory contents'
    # All results should start with ~/
    result.each do |r|
      assert r.start_with?('~/'), "#{r} should start with ~/"
    end
  end
end
