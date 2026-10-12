# frozen_string_literal: true

require_relative 'test_helper'

# zsh's SH_WORD_SPLIT option: field splitting of unquoted scalar
# parameter expansions. rubish is bash-compatible, so splitting is ON
# by default (unlike zsh); `unsetopt shwordsplit` gives zsh's default
# no-split behavior and `setopt shwordsplit` restores splitting.
class TestShwordsplit < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_shwordsplit_test')
  end

  def teardown
    Rubish::Builtins.set_zsh_option('sh_word_split', true)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  def test_enabled_by_default
    assert Rubish::Builtins.zsh_option_enabled?('sh_word_split')
  end

  def test_unquoted_expansion_splits_by_default
    execute('WORDS="foo bar baz"')
    execute("printf '[%s]' $WORDS > #{output_file}")
    assert_equal '[foo][bar][baz]', File.read(output_file)
  end

  def test_unsetopt_disables_splitting
    execute('WORDS="foo bar baz"')
    execute('unsetopt shwordsplit')
    execute("printf '[%s]' $WORDS > #{output_file}")
    assert_equal '[foo bar baz]', File.read(output_file)
  end

  def test_setopt_reenables_splitting
    execute('WORDS="foo bar"')
    execute('unsetopt shwordsplit')
    execute('setopt shwordsplit')
    execute("printf '[%s]' $WORDS > #{output_file}")
    assert_equal '[foo][bar]', File.read(output_file)
  end

  # zsh option names are case-insensitive and ignore underscores
  def test_underscored_option_name
    execute('WORDS="foo bar"')
    execute('unsetopt SH_WORD_SPLIT')
    execute("printf '[%s]' $WORDS > #{output_file}")
    assert_equal '[foo bar]', File.read(output_file)
  end

  def test_quoted_expansion_never_splits
    execute('WORDS="foo bar"')
    execute("printf '[%s]' \"$WORDS\" > #{output_file}")
    assert_equal '[foo bar]', File.read(output_file)
  end

  # Even in zsh, an empty unquoted scalar expansion is removed
  # (shwordsplit does not change that).
  def test_empty_expansion_still_elided_when_disabled
    execute('EMPTY=""')
    execute('unsetopt shwordsplit')
    execute("printf '[%s]' before $EMPTY after > #{output_file}")
    assert_equal '[before][after]', File.read(output_file)
  end

  # Builtins run through a separate expansion path (no codegen); the
  # option must be honored there too.
  def test_builtin_path_honors_disabled_splitting
    execute('WORDS="foo bar baz"')
    execute('unsetopt shwordsplit')
    output = capture_output { execute("printf '[%s]' $WORDS") }
    assert_equal '[foo bar baz]', output
  end

  # zsh word-splits unquoted command substitutions regardless of
  # shwordsplit.
  def test_command_substitution_still_splits_when_disabled
    execute('unsetopt shwordsplit')
    output = capture_output { execute("printf '[%s]' $(echo foo bar)") }
    assert_equal '[foo][bar]', output
  end

  # The option only governs scalar expansions. Unquoted array expansion
  # keeps rubish's bash-style behavior (elements joined then split)
  # whether the option is on or off — zsh's element-preserving unquoted
  # array expansion is not implemented, since the expansion joins the
  # elements into one string before word splitting happens.
  def test_array_expansion_unaffected
    execute('arr=("foo bar" baz)')
    execute('unsetopt shwordsplit')
    output = capture_output { execute("printf '[%s]' ${arr[@]}") }
    assert_equal '[foo][bar][baz]', output
  end
end
