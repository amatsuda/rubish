# frozen_string_literal: true

require_relative 'test_helper'

# zsh option names resolve through a memoized table: correct for every
# spelling, and cheap enough to be called on every word expansion
class TestZshOptionLookup < Test::Unit::TestCase
  def test_resolves_canonical_and_alternate_spellings
    assert_equal Rubish::Builtins.find_zsh_option('sh_word_split'), Rubish::Builtins.find_zsh_option('shwordsplit')
    assert_equal Rubish::Builtins.find_zsh_option('shwordsplit'), Rubish::Builtins.find_zsh_option('SH_WORD_SPLIT')
    assert_not_nil Rubish::Builtins.find_zsh_option('auto_cd')
  end

  def test_unknown_option_is_nil
    assert_nil Rubish::Builtins.find_zsh_option('no_such_option_rubish')
  end

  def test_lookup_is_fast_enough_for_per_expansion_use
    Rubish::Builtins.zsh_option_enabled?('sh_word_split') # warm up
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    5000.times { Rubish::Builtins.zsh_option_enabled?('sh_word_split') }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert elapsed < 0.1, "5000 lookups took #{(elapsed * 1000).round}ms; expected a memoized table"
  end

  def test_setopt_still_changes_the_value
    Rubish::Builtins.set_zsh_option('sh_word_split', true)
    assert_true Rubish::Builtins.zsh_option_enabled?('shwordsplit')
    Rubish::Builtins.set_zsh_option('sh_word_split', false)
    assert_false Rubish::Builtins.zsh_option_enabled?('shwordsplit')
  end
end
