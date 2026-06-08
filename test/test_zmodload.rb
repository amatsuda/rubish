# frozen_string_literal: true

require_relative 'test_helper'

class TestZmodload < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  # The builtin exists — `.zshrc` snippets that start with
  # `zmodload zsh/datetime` shouldn't abort with "command not found".
  def test_zmodload_is_builtin
    assert Rubish::Builtins.builtin?('zmodload')
  end

  # Loading any known zsh module is a silent success — rubish provides
  # the features (EPOCHREALTIME, int()/rint() in arithmetic, etc.)
  # natively, so there's nothing to actually load.
  def test_zmodload_succeeds_for_zsh_datetime
    result = Rubish::Builtins.run('zmodload', %w[zsh/datetime])
    assert result
  end

  def test_zmodload_succeeds_for_zsh_mathfunc
    result = Rubish::Builtins.run('zmodload', %w[zsh/mathfunc])
    assert result
  end

  def test_zmodload_succeeds_for_zsh_parameter
    result = Rubish::Builtins.run('zmodload', %w[zsh/parameter])
    assert result
  end

  # Unknown module names also succeed — we don't gate on the name
  # because the typical use is "best effort, fail open" in init scripts.
  def test_zmodload_succeeds_for_unknown_module
    result = Rubish::Builtins.run('zmodload', %w[zsh/notathing])
    assert result
  end

  # Flag-only invocations are accepted (zsh's `-L` lists loaded modules).
  def test_zmodload_dash_L_lists
    output = capture_stdout do
      Rubish::Builtins.run('zmodload', %w[-L])
    end
    # Lists the always-available emulated modules
    assert_match(/zsh\/datetime/, output)
    assert_match(/zsh\/mathfunc/, output)
  end

  # End-to-end: after `zmodload zsh/datetime`, EPOCHREALTIME yields a
  # current Unix timestamp string. (It's always available in rubish,
  # but starship's init script gates its presence on the zmodload call.)
  def test_epochrealtime_yields_current_time
    @repl.send(:execute, 'zmodload zsh/datetime')
    @repl.send(:execute, 'T=$EPOCHREALTIME')
    v = Rubish::Builtins.get_var('T').to_f
    now = Time.now.to_f
    assert (v - now).abs < 2.0, "EPOCHREALTIME (#{v}) not within 2s of now (#{now})"
  ensure
    Rubish::Builtins.delete_var('T')
  end

  # The canonical starship `__starship_get_time` body — this is the
  # primary integration that drove zmodload + math-func support.
  def test_starship_get_time_pattern
    @repl.send(:execute, 'zmodload zsh/datetime')
    @repl.send(:execute, 'zmodload zsh/mathfunc')
    @repl.send(:execute, '(( STARSHIP_CAPTURED_TIME = int(rint(EPOCHREALTIME * 1000)) ))')
    v = Rubish::Builtins.get_var('STARSHIP_CAPTURED_TIME').to_i
    # 2023-11-15 ≤ t < 2033-05-18 in ms
    assert v > 1_700_000_000_000
    assert v < 2_000_000_000_000
  ensure
    Rubish::Builtins.delete_var('STARSHIP_CAPTURED_TIME')
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
end
