# frozen_string_literal: true

require_relative 'test_helper'

class TestZshCompletion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    Rubish::Builtins.instance_variable_set(:@zsh_completion_initialized, false)
    Rubish::Builtins.instance_variable_set(:@zsh_completions, {})
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.instance_variable_set(:@zsh_completion_initialized, false)
    Rubish::Builtins.instance_variable_set(:@zsh_completions, {})
  end

  # ==========================================================================
  # compinit tests
  # ==========================================================================

  def test_compinit_is_builtin
    assert Rubish::Builtins.builtin?('compinit')
  end

  def test_compinit_initializes_system
    assert_false Rubish::Builtins.zsh_completion_initialized?
    result = Rubish::Builtins.run('compinit', [])
    assert result
    assert Rubish::Builtins.zsh_completion_initialized?
  end

  def test_compinit_with_options
    result = Rubish::Builtins.run('compinit', ['-u', '-C'])
    assert result
    assert Rubish::Builtins.zsh_completion_initialized?
  end

  def test_compinit_with_dumpfile
    result = Rubish::Builtins.run('compinit', ['-d', '/tmp/zcompdump'])
    assert result
  end

  def test_compinit_sets_up_default_completions
    Rubish::Builtins.run('compinit', [])
    # Check that some default completions are set up
    spec = Rubish::Builtins.get_completion_spec('git')
    assert_not_nil spec
  end

  def test_compinit_via_repl
    execute('compinit')
    assert Rubish::Builtins.zsh_completion_initialized?
  end

  # ==========================================================================
  # compdef tests
  # ==========================================================================

  def test_compdef_is_builtin
    assert Rubish::Builtins.builtin?('compdef')
  end

  def test_compdef_defines_completion
    result = Rubish::Builtins.run('compdef', ['_mycomp', 'mycommand'])
    assert result
    assert_equal '_mycomp', Rubish::Builtins.get_zsh_completion('mycommand')
  end

  def test_compdef_multiple_commands
    result = Rubish::Builtins.run('compdef', ['_mycomp', 'cmd1', 'cmd2', 'cmd3'])
    assert result
    assert_equal '_mycomp', Rubish::Builtins.get_zsh_completion('cmd1')
    assert_equal '_mycomp', Rubish::Builtins.get_zsh_completion('cmd2')
    assert_equal '_mycomp', Rubish::Builtins.get_zsh_completion('cmd3')
  end

  def test_compdef_no_override
    Rubish::Builtins.run('compdef', ['_first', 'mycmd'])
    Rubish::Builtins.run('compdef', ['-n', '_second', 'mycmd'])
    # Should still be _first because -n prevents override
    assert_equal '_first', Rubish::Builtins.get_zsh_completion('mycmd')
  end

  def test_compdef_delete
    Rubish::Builtins.run('compdef', ['_mycomp', 'mycmd'])
    assert_equal '_mycomp', Rubish::Builtins.get_zsh_completion('mycmd')

    Rubish::Builtins.run('compdef', ['-d', 'mycmd'])
    assert_nil Rubish::Builtins.get_zsh_completion('mycmd')
  end

  def test_compdef_lists_completions
    Rubish::Builtins.run('compdef', ['_git', 'git'])
    Rubish::Builtins.run('compdef', ['_ssh', 'ssh'])

    output = capture_output { Rubish::Builtins.run('compdef', []) }
    assert_match(/git: _git/, output)
    assert_match(/ssh: _ssh/, output)
  end

  def test_compdef_integrates_with_bash_complete
    Rubish::Builtins.run('compdef', ['_mycomp', 'mycmd'])

    # Should also register with bash-style completion system
    spec = Rubish::Builtins.get_completion_spec('mycmd')
    assert_not_nil spec
    assert_equal '_mycomp', spec[:function]
  end

  def test_compdef_via_repl
    execute('compdef _mycomp mycommand')
    assert_equal '_mycomp', Rubish::Builtins.get_zsh_completion('mycommand')
  end

  # ==========================================================================
  # Integration tests
  # ==========================================================================

  def test_type_identifies_compinit_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['compinit']) }
    assert_match(/compinit is a shell builtin/, output)
  end

  def test_type_identifies_compdef_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['compdef']) }
    assert_match(/compdef is a shell builtin/, output)
  end

  def test_common_zsh_pattern
    # Test the common "autoload -Uz compinit && compinit" pattern
    execute('compinit')
    execute('compdef _git git')
    assert Rubish::Builtins.zsh_completion_initialized?
    assert_equal '_git', Rubish::Builtins.get_zsh_completion('git')
  end
end
