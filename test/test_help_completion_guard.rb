# frozen_string_literal: true

require_relative 'test_helper'

# Tab completion learns a tool's subcommands by running `<cmd> --help`.
# Without the macOS sandbox that means executing whatever the user typed, so
# off-macOS only commands found on PATH are run, never ./scripts or paths.
class TestHelpCompletionGuard < Test::Unit::TestCase
  def setup
    @context = Rubish::Builtins.context
    @original = Rubish::Builtins.method(:help_sandbox_available?)
  end

  def teardown
    Rubish::Builtins.define_singleton_method(:help_sandbox_available?, @original)
  end

  def stub_sandbox(available)
    Rubish::Builtins.define_singleton_method(:help_sandbox_available?) { available }
  end

  def test_path_command_is_allowed_without_sandbox
    stub_sandbox(false)
    assert_true @context.help_command_allowed?('ls')
  end

  def test_relative_script_is_refused_without_sandbox
    stub_sandbox(false)
    assert_false @context.help_command_allowed?('./deploy.sh')
    assert_false @context.help_command_allowed?('../bin/tool')
    assert_false @context.help_command_allowed?('/tmp/downloaded')
  end

  def test_unknown_command_is_refused_without_sandbox
    stub_sandbox(false)
    assert_false @context.help_command_allowed?('no_such_command_rubish_xyz')
  end

  def test_everything_is_allowed_with_sandbox
    stub_sandbox(true)
    assert_true @context.help_command_allowed?('./deploy.sh')
    assert_true @context.help_command_allowed?('ls')
  end

  def test_parse_help_for_refused_command_runs_nothing
    stub_sandbox(false)
    Dir.mktmpdir('rubish_help_guard') do |dir|
      marker = File.join(dir, 'ran')
      script = File.join(dir, 'tool')
      File.write(script, "#!/bin/sh\ntouch #{marker}\necho 'usage: tool [options] <command>'\n")
      File.chmod(0o755, script)
      assert_nil @context.parse_help_for_command(script)
      assert_false File.exist?(marker), '--help probe must not execute an untrusted path'
    end
  end

  def test_help_command_is_split_into_argv_not_a_shell_string
    assert_equal %w[gem help commands], Rubish::Builtins.help_command_argv('gem help commands')
    assert_equal ['my tool', '--help'], Rubish::Builtins.help_command_argv("'my tool' --help")
  end
end
