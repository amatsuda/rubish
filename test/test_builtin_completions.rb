# frozen_string_literal: true

require_relative 'test_helper'

class TestBuiltinCompletions < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_completion_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)

    Rubish::Builtins.instance_variable_set(:@compreply, [])
    Rubish::Builtins.clear_completions
    Rubish::Builtins.setup_default_completions
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.clear_completion_context
    Rubish::Builtins.instance_variable_set(:@compreply, [])
  end

  # ==========================================================================
  # Builtin completion function registration tests
  # ==========================================================================

  def test_builtin_completion_function_registered
    assert Rubish::Builtins.builtin_completion_function?('_git')
    assert Rubish::Builtins.builtin_completion_function?('_ssh')
    assert Rubish::Builtins.builtin_completion_function?('_cd')
    assert Rubish::Builtins.builtin_completion_function?('_make')
    assert Rubish::Builtins.builtin_completion_function?('_man')
    assert Rubish::Builtins.builtin_completion_function?('_kill')
  end

  def test_default_completions_registered
    assert_not_nil Rubish::Builtins.completions['git']
    assert_equal '_git', Rubish::Builtins.completions['git'][:function]

    assert_not_nil Rubish::Builtins.completions['ssh']
    assert_equal '_ssh', Rubish::Builtins.completions['ssh'][:function]

    assert_not_nil Rubish::Builtins.completions['cd']
    assert_equal '_cd', Rubish::Builtins.completions['cd'][:function]

    assert_not_nil Rubish::Builtins.completions['make']
    assert_equal '_make', Rubish::Builtins.completions['make'][:function]

    assert_not_nil Rubish::Builtins.completions['man']
    assert_equal '_man', Rubish::Builtins.completions['man'][:function]

    assert_not_nil Rubish::Builtins.completions['kill']
    assert_equal '_kill', Rubish::Builtins.completions['kill'][:function]
  end

  # ==========================================================================
  # Git completion tests
  # ==========================================================================

  def test_git_complete_subcommands
    Rubish::Builtins.set_completion_context(
      line: 'git ',
      point: 4,
      words: ['git', ''],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_git', 'git', '', 'git')

    completions = Rubish::Builtins.compreply
    assert completions.include?('add')
    assert completions.include?('commit')
    assert completions.include?('push')
    assert completions.include?('pull')
    assert completions.include?('branch')
    assert completions.include?('checkout')
  end

  def test_git_complete_subcommands_with_prefix
    Rubish::Builtins.set_completion_context(
      line: 'git co',
      point: 6,
      words: ['git', 'co'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_git', 'git', 'co', 'git')

    completions = Rubish::Builtins.compreply
    assert completions.include?('commit')
    assert completions.include?('config')
    assert completions.include?('column')
    assert completions.none? { |c| c.start_with?('add') }
  end

  def test_git_complete_options
    Rubish::Builtins.set_completion_context(
      line: 'git --',
      point: 6,
      words: ['git', '--'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_git', 'git', '--', 'git')

    completions = Rubish::Builtins.compreply
    assert completions.include?('--version')
    assert completions.include?('--help')
  end

  def test_git_add_options
    Rubish::Builtins.set_completion_context(
      line: 'git add -',
      point: 9,
      words: ['git', 'add', '-'],
      cword: 2
    )

    Rubish::Builtins.call_builtin_completion_function('_git', 'git', '-', 'add')

    completions = Rubish::Builtins.compreply
    assert completions.any? { |c| c.start_with?('-') }
    assert completions.include?('--all') || completions.include?('-A')
  end

  def test_git_commit_options
    Rubish::Builtins.set_completion_context(
      line: 'git commit --',
      point: 13,
      words: ['git', 'commit', '--'],
      cword: 2
    )

    Rubish::Builtins.call_builtin_completion_function('_git', 'git', '--', 'commit')

    completions = Rubish::Builtins.compreply
    assert completions.include?('--amend')
    assert completions.include?('--message')
  end

  def test_git_stash_subcommands
    Rubish::Builtins.set_completion_context(
      line: 'git stash ',
      point: 10,
      words: ['git', 'stash', ''],
      cword: 2
    )

    Rubish::Builtins.call_builtin_completion_function('_git', 'git', '', 'stash')

    completions = Rubish::Builtins.compreply
    assert completions.include?('list')
    assert completions.include?('pop')
    assert completions.include?('apply')
    assert completions.include?('drop')
  end

  def test_git_remote_subcommands
    Rubish::Builtins.set_completion_context(
      line: 'git remote ',
      point: 11,
      words: ['git', 'remote', ''],
      cword: 2
    )

    Rubish::Builtins.call_builtin_completion_function('_git', 'git', '', 'remote')

    completions = Rubish::Builtins.compreply
    assert completions.include?('add')
    assert completions.include?('remove')
    assert completions.include?('show')
  end

  # ==========================================================================
  # SSH completion tests
  # ==========================================================================

  def test_ssh_complete_options
    Rubish::Builtins.set_completion_context(
      line: 'ssh -',
      point: 5,
      words: ['ssh', '-'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_ssh', 'ssh', '-', 'ssh')

    completions = Rubish::Builtins.compreply
    assert completions.any? { |c| c.start_with?('-') }
    assert completions.include?('-v')
    assert completions.include?('-p')
    assert completions.include?('-i')
  end

  def test_ssh_complete_hosts_from_etc_hosts
    # Create a mock /etc/hosts content by testing the actual function
    # The function reads from /etc/hosts and ~/.ssh/config
    Rubish::Builtins.set_completion_context(
      line: 'ssh local',
      point: 9,
      words: ['ssh', 'local'],
      cword: 1
    )

    # Just verify the function runs without error
    result = Rubish::Builtins.call_builtin_completion_function('_ssh', 'ssh', 'local', 'ssh')
    assert result
  end

  # ==========================================================================
  # CD completion tests
  # ==========================================================================

  def test_cd_complete_directories
    # Create some directories
    FileUtils.mkdir('testdir1')
    FileUtils.mkdir('testdir2')
    FileUtils.touch('testfile.txt')

    ENV['cur'] = 'test'
    Rubish::Builtins.set_completion_context(
      line: 'cd test',
      point: 7,
      words: ['cd', 'test'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_cd', 'cd', 'test', 'cd')

    completions = Rubish::Builtins.compreply
    # Should include directories but not files
    assert completions.any? { |c| c.include?('testdir') }
    assert completions.none? { |c| c.include?('testfile') }
  end

  def test_cd_complete_options
    Rubish::Builtins.set_completion_context(
      line: 'cd -',
      point: 4,
      words: ['cd', '-'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_cd', 'cd', '-', 'cd')

    completions = Rubish::Builtins.compreply
    assert completions.include?('-L')
    assert completions.include?('-P')
  end

  # ==========================================================================
  # Make completion tests
  # ==========================================================================

  def test_make_complete_targets
    # Create a Makefile
    File.write('Makefile', <<~MAKEFILE)
      all: build test

      build:
      \t@echo "Building..."

      test:
      \t@echo "Testing..."

      clean:
      \t@rm -rf build/

      .PHONY: all build test clean
    MAKEFILE

    ENV['cur'] = ''
    Rubish::Builtins.set_completion_context(
      line: 'make ',
      point: 5,
      words: ['make', ''],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_make', 'make', '', 'make')

    completions = Rubish::Builtins.compreply
    assert completions.include?('all')
    assert completions.include?('build')
    assert completions.include?('test')
    assert completions.include?('clean')
  end

  def test_make_complete_targets_with_prefix
    # Create a Makefile
    File.write('Makefile', <<~MAKEFILE)
      build: compile link

      build-debug:
      \t@echo "Debug build"

      build-release:
      \t@echo "Release build"
    MAKEFILE

    ENV['cur'] = 'build'
    Rubish::Builtins.set_completion_context(
      line: 'make build',
      point: 10,
      words: ['make', 'build'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_make', 'make', 'build', 'make')

    completions = Rubish::Builtins.compreply
    assert completions.include?('build')
    assert completions.include?('build-debug')
    assert completions.include?('build-release')
  end

  def test_make_complete_options
    Rubish::Builtins.set_completion_context(
      line: 'make -',
      point: 6,
      words: ['make', '-'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_make', 'make', '-', 'make')

    completions = Rubish::Builtins.compreply
    assert completions.any? { |c| c.start_with?('-') }
    assert completions.include?('-f') || completions.include?('--file')
    assert completions.include?('-j') || completions.include?('--jobs')
  end

  # ==========================================================================
  # Man completion tests
  # ==========================================================================

  def test_man_complete_options
    Rubish::Builtins.set_completion_context(
      line: 'man -',
      point: 5,
      words: ['man', '-'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_man', 'man', '-', 'man')

    completions = Rubish::Builtins.compreply
    assert completions.any? { |c| c.start_with?('-') }
    assert completions.include?('-k') || completions.include?('--apropos')
    assert completions.include?('-a') || completions.include?('--all')
  end

  def test_man_complete_sections
    Rubish::Builtins.set_completion_context(
      line: 'man -s ',
      point: 7,
      words: ['man', '-s', ''],
      cword: 2
    )

    Rubish::Builtins.call_builtin_completion_function('_man', 'man', '', '-s')

    completions = Rubish::Builtins.compreply
    assert completions.include?('1')
    assert completions.include?('3')
    assert completions.include?('8')
  end

  # ==========================================================================
  # Kill completion tests
  # ==========================================================================

  def test_kill_complete_signals
    Rubish::Builtins.set_completion_context(
      line: 'kill -',
      point: 6,
      words: ['kill', '-'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_kill', 'kill', '-', 'kill')

    completions = Rubish::Builtins.compreply
    assert completions.any? { |c| c.start_with?('-') }
    # Should include signal options like -l, -s
    assert completions.include?('-l'), 'Should include -l option'
    assert completions.include?('-s'), 'Should include -s option'
  end

  def test_kill_complete_signal_names
    Rubish::Builtins.set_completion_context(
      line: 'kill -s HU',
      point: 10,
      words: ['kill', '-s', 'HU'],
      cword: 2
    )

    Rubish::Builtins.call_builtin_completion_function('_kill', 'kill', 'HU', '-s')

    completions = Rubish::Builtins.compreply
    assert completions.include?('HUP')
  end

  def test_kill_complete_long_options
    Rubish::Builtins.set_completion_context(
      line: 'kill --',
      point: 7,
      words: ['kill', '--'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_kill', 'kill', '--', 'kill')

    completions = Rubish::Builtins.compreply
    assert completions.include?('--signal')
    assert completions.include?('--list')
  end

  # ==========================================================================
  # Integration tests
  # ==========================================================================

  def test_call_builtin_completion_function_returns_true
    Rubish::Builtins.set_completion_context(
      line: 'git ',
      point: 4,
      words: ['git', ''],
      cword: 1
    )

    result = Rubish::Builtins.call_builtin_completion_function('_git', 'git', '', 'git')
    assert result, 'call_builtin_completion_function should return true for valid function'
  end

  def test_call_builtin_completion_function_returns_false_for_unknown
    result = Rubish::Builtins.call_builtin_completion_function('_nonexistent', 'cmd', '', '')
    assert_false result, 'call_builtin_completion_function should return false for unknown function'
  end

  def test_builtin_completion_function_not_registered
    assert_false Rubish::Builtins.builtin_completion_function?('_nonexistent')
  end
end
