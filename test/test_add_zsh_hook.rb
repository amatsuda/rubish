# frozen_string_literal: true

require_relative 'test_helper'

class TestAddZshHook < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_dir = Dir.pwd
    @original_env = ENV.to_h
    @tempdir = Dir.mktmpdir('rubish_zsh_hook_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    # The cd builtin sets ENV['PWD']; if we don't restore the env, the
    # next test's `pwd` builtin (which reads ENV['PWD'] first) reports
    # this test's last cwd instead of where it actually is.
    ENV.replace(@original_env)
    FileUtils.rm_rf(@tempdir)
    %w[chpwd precmd preexec periodic zshexit zshaddhistory zsh_directory_name].each do |h|
      Rubish::Builtins.unset_array("#{h}_functions")
    end
  end

  # `add-zsh-hook NAME FUNC` appends FUNC to NAME_functions.
  def test_add_zsh_hook_basic_add
    Rubish::Builtins.run('add-zsh-hook', %w[precmd starship_precmd])
    assert_equal ['starship_precmd'], Rubish::Builtins.get_array('precmd_functions')
  end

  # Re-adding the same function is a no-op (zsh's add-zsh-hook dedupes
  # by default — many .zshrc snippets source themselves repeatedly).
  def test_add_zsh_hook_deduplicates
    Rubish::Builtins.run('add-zsh-hook', %w[precmd starship_precmd])
    Rubish::Builtins.run('add-zsh-hook', %w[precmd starship_precmd])
    assert_equal ['starship_precmd'], Rubish::Builtins.get_array('precmd_functions')
  end

  # Distinct functions accumulate in registration order.
  def test_add_zsh_hook_multiple_functions
    Rubish::Builtins.run('add-zsh-hook', %w[precmd one])
    Rubish::Builtins.run('add-zsh-hook', %w[precmd two])
    assert_equal %w[one two], Rubish::Builtins.get_array('precmd_functions')
  end

  # `-d` removes a previously registered function.
  def test_add_zsh_hook_delete
    Rubish::Builtins.run('add-zsh-hook', %w[precmd one])
    Rubish::Builtins.run('add-zsh-hook', %w[precmd two])
    Rubish::Builtins.run('add-zsh-hook', %w[-d precmd one])
    assert_equal ['two'], Rubish::Builtins.get_array('precmd_functions')
  end

  # Unknown hook names are rejected — catches `.zshrc` typos at the
  # source instead of letting them silently never fire.
  def test_add_zsh_hook_rejects_unknown_hook
    result = capture_stderr do
      Rubish::Builtins.run('add-zsh-hook', %w[notahook foo])
    end
    refute result[:return_value]
    assert_match(/unknown hook/, result[:stderr])
  end

  # `-L` prints currently installed hooks in a format that would
  # re-register them if pasted back — matches real add-zsh-hook -L.
  def test_add_zsh_hook_list
    Rubish::Builtins.run('add-zsh-hook', %w[precmd one])
    Rubish::Builtins.run('add-zsh-hook', %w[chpwd two])
    output = capture_stdout do
      Rubish::Builtins.run('add-zsh-hook', %w[-L])
    end
    assert_match(/add-zsh-hook precmd one/, output)
    assert_match(/add-zsh-hook chpwd two/, output)
  end

  # End-to-end: register a precmd via add-zsh-hook, then verify
  # fire_zsh_hooks invokes it. This is the path the REPL takes
  # immediately before each prompt render.
  def test_fire_zsh_hooks_runs_precmd_function
    @repl.send(:execute, 'precmd_calls=0')
    @repl.send(:execute, 'my_precmd() { precmd_calls=$((precmd_calls + 1)); }')
    @repl.send(:execute, 'add-zsh-hook precmd my_precmd')

    @repl.send(:fire_zsh_hooks, 'precmd')
    @repl.send(:fire_zsh_hooks, 'precmd')

    assert_equal '2', Rubish::Builtins.get_var('precmd_calls')
  ensure
    Rubish::Builtins.delete_var('precmd_calls')
    Rubish::Builtins.current_state.function_remover&.call('my_precmd')
  end

  # preexec receives the command string as $1 (matching zsh).
  # starship_preexec relies on this to stash a start timestamp.
  def test_fire_zsh_hooks_passes_command_to_preexec
    @repl.send(:execute, 'last_preexec_cmd=')
    @repl.send(:execute, 'my_preexec() { last_preexec_cmd="$1"; }')
    @repl.send(:execute, 'add-zsh-hook preexec my_preexec')

    @repl.send(:fire_zsh_hooks, 'preexec', 'ls -la')

    assert_equal 'ls -la', Rubish::Builtins.get_var('last_preexec_cmd')
  ensure
    Rubish::Builtins.delete_var('last_preexec_cmd')
    Rubish::Builtins.current_state.function_remover&.call('my_preexec')
  end

  # The cd builtin fires chpwd_functions after a successful directory
  # change. (zsh-style — many prompt themers use this to invalidate
  # cached vcs info.)
  def test_cd_fires_chpwd_hook
    @repl.send(:execute, 'chpwd_calls=0')
    @repl.send(:execute, 'my_chpwd() { chpwd_calls=$((chpwd_calls + 1)); }')
    @repl.send(:execute, 'add-zsh-hook chpwd my_chpwd')

    @repl.send(:execute, "cd #{@tempdir}")
    @repl.send(:execute, "cd /tmp")

    assert_equal '2', Rubish::Builtins.get_var('chpwd_calls')
  ensure
    Rubish::Builtins.delete_var('chpwd_calls')
    Rubish::Builtins.current_state.function_remover&.call('my_chpwd')
  end

  # The last command's $? must survive precmd hooks — the prompt
  # expansion that runs immediately after has to see the original
  # status. (Individual hooks that care about $? save it on entry,
  # matching zsh.)
  def test_fire_zsh_hooks_preserves_last_status
    @repl.send(:execute, 'my_precmd() { true; }')
    @repl.send(:execute, 'add-zsh-hook precmd my_precmd')
    @repl.instance_variable_set(:@last_status, 42)

    @repl.send(:fire_zsh_hooks, 'precmd')

    assert_equal 42, @repl.instance_variable_get(:@last_status)
  ensure
    Rubish::Builtins.current_state.function_remover&.call('my_precmd')
  end

  # A hook function that references an undefined function name is
  # skipped — no error, the rest of the chain still runs. Mirrors
  # zsh, which prints a warning but keeps going.
  def test_fire_zsh_hooks_skips_undefined_functions
    @repl.send(:execute, 'precmd_calls=0')
    @repl.send(:execute, 'present_precmd() { precmd_calls=$((precmd_calls + 1)); }')
    Rubish::Builtins.run('add-zsh-hook', %w[precmd missing_precmd])
    Rubish::Builtins.run('add-zsh-hook', %w[precmd present_precmd])

    @repl.send(:fire_zsh_hooks, 'precmd')

    assert_equal '1', Rubish::Builtins.get_var('precmd_calls')
  ensure
    Rubish::Builtins.delete_var('precmd_calls')
    Rubish::Builtins.current_state.function_remover&.call('present_precmd')
  end

  private

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    rv = yield
    {return_value: rv, stderr: $stderr.string}
  ensure
    $stderr = original
  end
end
