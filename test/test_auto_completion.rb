# frozen_string_literal: true

require_relative 'test_helper'

class TestAutoCompletion < Test::Unit::TestCase
  def setup
    Rubish::Builtins.instance_variable_set(:@compreply, [])
    Rubish::Builtins.instance_variable_set(:@help_completion_cache, {})
    Rubish::Builtins.clear_completions
    Rubish::Builtins.setup_default_completions
  end

  def teardown
    Rubish::Builtins.clear_completion_context
    Rubish::Builtins.instance_variable_set(:@compreply, [])
    Rubish::Builtins.instance_variable_set(:@help_completion_cache, {})
  end

  # ==========================================================================
  # Auto completion function registration
  # ==========================================================================

  def test_auto_completion_function_registered
    assert Rubish::Builtins.builtin_completion_function?('_auto')
  end

  # ==========================================================================
  # Help command sources
  # ==========================================================================

  def test_help_command_sources_defined
    sources = Rubish::Builtins::HELP_COMMAND_SOURCES
    assert_equal 'bundle --help', sources['bundle']
    assert_equal 'gem help commands', sources['gem']
    assert_equal 'brew commands', sources['brew']
    assert_equal 'npm help', sources['npm']
    assert_equal 'yarn --help', sources['yarn']
  end

  def test_help_command_sources_excludes_git
    # git has dedicated _git completion function
    sources = Rubish::Builtins::HELP_COMMAND_SOURCES
    assert_nil sources['git']
  end

  # ==========================================================================
  # Cache TTL
  # ==========================================================================

  def test_cache_ttl_is_30_minutes
    assert_equal 1800, Rubish::Builtins::HELP_CACHE_TTL
  end

  # ==========================================================================
  # Help output parsing
  # ==========================================================================

  def test_parse_help_output_table_format
    # gem help commands style
    help_text = <<~HELP
      GEM commands are:

          build             Build a gem from a gemspec
          cert              Manage RubyGems certificates
          check             Check a gem repository
          install           Install a gem into the local repository
          uninstall         Uninstall gems from the local repository
    HELP

    result = Rubish::Builtins.parse_help_output(help_text)
    assert_includes result[:subcommands], 'build'
    assert_includes result[:subcommands], 'cert'
    assert_includes result[:subcommands], 'check'
    assert_includes result[:subcommands], 'install'
    assert_includes result[:subcommands], 'uninstall'
  end

  def test_parse_help_output_simple_list_format
    # brew commands style
    help_text = <<~HELP
      ==> Built-in commands
      analytics
      autoremove
      casks
      cleanup
      install
      uninstall
    HELP

    result = Rubish::Builtins.parse_help_output(help_text)
    assert_includes result[:subcommands], 'analytics'
    assert_includes result[:subcommands], 'autoremove'
    assert_includes result[:subcommands], 'casks'
    assert_includes result[:subcommands], 'cleanup'
    assert_includes result[:subcommands], 'install'
    assert_includes result[:subcommands], 'uninstall'
  end

  def test_parse_help_output_options
    help_text = <<~HELP
      Options:
        -h, --help     Show this message
        -v, --version  Show version
        --verbose      Enable verbose mode
        -q, --quiet    Quiet mode
    HELP

    result = Rubish::Builtins.parse_help_output(help_text)
    assert_includes result[:options], '-h'
    assert_includes result[:options], '--help'
    assert_includes result[:options], '-v'
    assert_includes result[:options], '--version'
    assert_includes result[:options], '--verbose'
    assert_includes result[:options], '-q'
    assert_includes result[:options], '--quiet'
  end

  def test_parse_help_output_man_page_format
    # bundle --help style with man page formatting
    help_text = <<~HELP
      BUNDLE COMMANDS
             bundle install(1)
                    Install the gems specified by the Gemfile

             bundle update(1)
                    Update dependencies to their latest versions

             bundle exec(1)
                    Execute a command in the context of the bundle
    HELP

    result = Rubish::Builtins.parse_help_output(help_text)
    assert_includes result[:subcommands], 'install'
    assert_includes result[:subcommands], 'update'
    assert_includes result[:subcommands], 'exec'
  end

  def test_parse_help_output_mixed_format
    help_text = <<~HELP
      Usage: mycli [options] <command>

      Commands:
        init        Initialize a new project
        build       Build the project
        test        Run tests

      Options:
        -h, --help     Show help
        -v, --version  Show version
    HELP

    result = Rubish::Builtins.parse_help_output(help_text)
    assert_includes result[:subcommands], 'init'
    assert_includes result[:subcommands], 'build'
    assert_includes result[:subcommands], 'test'
    assert_includes result[:options], '-h'
    assert_includes result[:options], '--help'
    assert_includes result[:options], '-v'
    assert_includes result[:options], '--version'
  end

  def test_parse_help_output_removes_ansi_codes
    help_text = "\e[1mCommands:\e[0m\n  \e[32minit\e[0m    Initialize\n  \e[32mbuild\e[0m   Build"

    result = Rubish::Builtins.parse_help_output(help_text)
    assert_includes result[:subcommands], 'init'
    assert_includes result[:subcommands], 'build'
  end

  def test_parse_help_output_skips_numeric_options
    help_text = <<~HELP
      Options:
        -1  Single column output
        -2  Two column output
        -h  Show help
    HELP

    result = Rubish::Builtins.parse_help_output(help_text)
    refute_includes result[:options], '-1'
    refute_includes result[:options], '-2'
    assert_includes result[:options], '-h'
  end

  # ==========================================================================
  # Caching
  # ==========================================================================

  def test_parse_help_caches_results
    # Manually populate cache
    Rubish::Builtins.instance_variable_get(:@help_completion_cache)['testcmd'] = {
      subcommands: ['cached_sub'],
      options: ['--cached'],
      timestamp: Time.now
    }

    result = Rubish::Builtins.parse_help_for_command('testcmd')
    assert_equal ['cached_sub'], result[:subcommands]
    assert_equal ['--cached'], result[:options]
  end

  def test_parse_help_cache_expires
    # Populate cache with old timestamp
    Rubish::Builtins.instance_variable_get(:@help_completion_cache)['expiredcmd'] = {
      subcommands: ['old_sub'],
      options: ['--old'],
      timestamp: Time.now - 3600  # 1 hour ago, beyond 30 min TTL
    }

    # Should return nil since command doesn't exist and cache is expired
    result = Rubish::Builtins.parse_help_for_command('expiredcmd')
    assert_nil result
  end

  # ==========================================================================
  # Auto completion integration
  # ==========================================================================

  def test_auto_completion_subcommands
    # Pre-populate cache to avoid actual command execution
    Rubish::Builtins.instance_variable_get(:@help_completion_cache)['testcli'] = {
      subcommands: ['init', 'build', 'test', 'deploy'],
      options: ['--help', '--version'],
      timestamp: Time.now
    }

    Rubish::Builtins.set_completion_context(
      line: 'testcli ',
      point: 8,
      words: ['testcli', ''],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_auto', 'testcli', '', 'testcli')
    completions = Rubish::Builtins.compreply

    assert_includes completions, 'init'
    assert_includes completions, 'build'
    assert_includes completions, 'test'
    assert_includes completions, 'deploy'
  end

  def test_auto_completion_subcommands_with_prefix
    Rubish::Builtins.instance_variable_get(:@help_completion_cache)['testcli'] = {
      subcommands: ['init', 'install', 'info', 'build'],
      options: ['--help'],
      timestamp: Time.now
    }

    Rubish::Builtins.set_completion_context(
      line: 'testcli in',
      point: 10,
      words: ['testcli', 'in'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_auto', 'testcli', 'in', 'testcli')
    completions = Rubish::Builtins.compreply

    assert_includes completions, 'init'
    assert_includes completions, 'install'
    assert_includes completions, 'info'
    refute_includes completions, 'build'
  end

  def test_auto_completion_options
    Rubish::Builtins.instance_variable_get(:@help_completion_cache)['testcli'] = {
      subcommands: ['init', 'build'],
      options: ['--help', '--version', '--verbose', '-h', '-v'],
      timestamp: Time.now
    }

    Rubish::Builtins.set_completion_context(
      line: 'testcli --',
      point: 10,
      words: ['testcli', '--'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_auto', 'testcli', '--', 'testcli')
    completions = Rubish::Builtins.compreply

    assert_includes completions, '--help'
    assert_includes completions, '--version'
    assert_includes completions, '--verbose'
    refute_includes completions, '-h'  # doesn't start with '--'
  end

  def test_auto_completion_options_short
    Rubish::Builtins.instance_variable_get(:@help_completion_cache)['testcli'] = {
      subcommands: ['init'],
      options: ['--help', '-h', '-v', '-q'],
      timestamp: Time.now
    }

    Rubish::Builtins.set_completion_context(
      line: 'testcli -',
      point: 9,
      words: ['testcli', '-'],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_auto', 'testcli', '-', 'testcli')
    completions = Rubish::Builtins.compreply

    assert_includes completions, '--help'
    assert_includes completions, '-h'
    assert_includes completions, '-v'
    assert_includes completions, '-q'
  end

  # ==========================================================================
  # Zsh completion file parsing
  # ==========================================================================

  def test_zsh_fpath_returns_array
    fpath = Rubish::Builtins.zsh_fpath
    assert_kind_of Array, fpath
    # If zsh is installed, fpath should have entries
    # If not, it should be an empty array (graceful fallback)
  end

  def test_parse_zsh_completion_describe_pattern
    content = <<~ZSH
      #compdef mycmd

      _mycmd() {
        local -a commands
        commands=(
          'add:Add something'
          'remove:Remove something'
          'list:List items'
        )
        _describe 'command' commands
      }
    ZSH

    # Manually test parsing logic
    subcommands = []
    content.scan(/'([a-z][-a-z0-9_]*):[^']*'/).each do |match|
      subcommands << match[0]
    end

    assert_includes subcommands, 'add'
    assert_includes subcommands, 'remove'
    assert_includes subcommands, 'list'
  end

  def test_parse_zsh_completion_array_pattern
    content = <<~ZSH
      commands=( add build check clean install uninstall )
    ZSH

    subcommands = []
    content.scan(/(?:commands?|cmds|subcmds)\s*=\s*\(\s*([^)]+)\)/m).each do |match|
      match[0].scan(/([a-z][-a-z0-9_]+)/).each do |cmd|
        subcommands << cmd[0] if cmd[0].length < 25
      end
    end

    assert_includes subcommands, 'add'
    assert_includes subcommands, 'build'
    assert_includes subcommands, 'check'
    assert_includes subcommands, 'clean'
    assert_includes subcommands, 'install'
    assert_includes subcommands, 'uninstall'
  end

  def test_parse_zsh_completion_options_pattern
    content = <<~ZSH
      _arguments \\
        '--help[show help]' \\
        '-h[short help]' \\
        '--version[show version]' \\
        '-v[verbose]'
    ZSH

    options = []
    content.scan(/['"]\{?(-[a-zA-Z]|--[a-zA-Z][-a-zA-Z0-9_]*)/).each do |match|
      options << match[0]
    end

    assert_includes options, '--help'
    assert_includes options, '-h'
    assert_includes options, '--version'
    assert_includes options, '-v'
  end

  def test_parse_zsh_completion_file_returns_nil_for_missing_file
    result = Rubish::Builtins.parse_zsh_completion_file('nonexistent_command_xyz')
    assert_nil result
  end

  def test_find_zsh_completion_file_returns_nil_for_missing
    result = Rubish::Builtins.find_zsh_completion_file('nonexistent_command_xyz')
    assert_nil result
  end

  def test_extract_zsh_completion_commands_call_program
    content = <<~ZSH
      commands=( ${(f)"$(_call_program commands cargo --list)"} )
      flags=( ${(f)"$(_call_program flags cargo -Z help)"} )
    ZSH

    cmds = Rubish::Builtins.extract_zsh_completion_commands(content, 'cargo')
    assert_includes cmds, 'cargo --list'
    refute_includes cmds, 'cargo -Z help'  # 'flags' tag, not 'commands'
  end

  def test_extract_zsh_completion_commands_dollar_paren
    content = <<~ZSH
      cmds=$(cargo --list)
      other=$(cargo install --list)
    ZSH

    cmds = Rubish::Builtins.extract_zsh_completion_commands(content, 'cargo')
    assert_includes cmds, 'cargo --list'
    refute_includes cmds, 'cargo install --list'  # Not simple list pattern
  end

  def test_extract_zsh_completion_commands_filters_non_list
    content = <<~ZSH
      $(brew doctor --list-checks)
      $(brew formulae)
    ZSH

    cmds = Rubish::Builtins.extract_zsh_completion_commands(content, 'brew')
    assert_empty cmds  # Neither matches simple list pattern
  end

  def test_zsh_completion_preferred_over_help_when_available
    # Pre-populate cache with zsh result
    Rubish::Builtins.instance_variable_get(:@help_completion_cache)['zshcmd'] = {
      subcommands: ['zsh-sub1', 'zsh-sub2', 'zsh-sub3'],
      options: ['--zsh-opt'],
      source: :zsh,
      timestamp: Time.now
    }

    Rubish::Builtins.set_completion_context(
      line: 'zshcmd ',
      point: 7,
      words: ['zshcmd', ''],
      cword: 1
    )

    Rubish::Builtins.call_builtin_completion_function('_auto', 'zshcmd', '', 'zshcmd')
    completions = Rubish::Builtins.compreply

    assert_includes completions, 'zsh-sub1'
    assert_includes completions, 'zsh-sub2'
    assert_includes completions, 'zsh-sub3'
  end

  # ==========================================================================
  # Sandbox security tests
  # ==========================================================================

  def test_sandbox_timeout
    # Verify timeout works (command should fail, not hang)
    start = Time.now
    output, success = Rubish::Builtins.run_sandboxed_help_command('sleep 10')
    elapsed = Time.now - start

    assert_false success
    assert elapsed < 5, "Timeout should have triggered in ~2 seconds, took #{elapsed}s"
  end

  def test_sandbox_blocks_network
    # Verify network access is blocked
    output, success = Rubish::Builtins.run_sandboxed_help_command('curl -s --max-time 1 https://example.com')
    assert_false success
  end

  # Regression test: completion should not create files
  # Before the sandbox, typing "touch[space]" would execute "touch --help"
  # which on some systems creates a file named "--help" or has other side effects
  def test_sandbox_touch_completion_does_not_create_files
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        # Clear cache to force help command execution
        Rubish::Builtins.instance_variable_set(:@help_completion_cache, {})

        # Record files before completion
        files_before = Dir.glob('*', base: tmpdir)

        # Trigger completion for touch command (simulates typing "touch ")
        Rubish::Builtins.set_completion_context(
          line: 'touch ',
          point: 6,
          words: ['touch', ''],
          cword: 1
        )
        Rubish::Builtins.call_builtin_completion_function('_auto', 'touch', '', 'touch')

        # Also directly test the sandboxed help command
        Rubish::Builtins.run_sandboxed_help_command('touch --help')

        # Record files after completion
        files_after = Dir.glob('*', base: tmpdir)

        # No new files should have been created
        new_files = files_after - files_before
        assert_empty new_files, "Completion created unexpected files: #{new_files.inspect}"
      end
    end
  end

  # Regression test: completion should not delete files
  def test_sandbox_rm_completion_does_not_delete_files
    Dir.mktmpdir do |tmpdir|
      # Create a test file
      test_file = File.join(tmpdir, 'testfile.txt')
      File.write(test_file, 'test content')

      Dir.chdir(tmpdir) do
        # Clear cache to force help command execution
        Rubish::Builtins.instance_variable_set(:@help_completion_cache, {})

        # Trigger completion for rm command (simulates typing "rm ")
        Rubish::Builtins.set_completion_context(
          line: 'rm ',
          point: 3,
          words: ['rm', ''],
          cword: 1
        )
        Rubish::Builtins.call_builtin_completion_function('_auto', 'rm', '', 'rm')

        # Also directly test the sandboxed help command
        Rubish::Builtins.run_sandboxed_help_command('rm --help')

        # Test file should still exist
        assert File.exist?(test_file), 'Completion deleted the test file!'
      end
    end
  end
end
