# frozen_string_literal: true

require_relative 'test_helper'

# History expansion must leave the `!` of `${!name}`, `${!arr[@]}` and
# `${!prefix*}` alone: those are parameter expansions, not event designators
class TestHistoryIndirectExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @saved_history = Reline::HISTORY.to_a
    Reline::HISTORY.clear
    Reline::HISTORY.push('echo previous')
    execute('set -H')
  end

  def teardown
    Reline::HISTORY.clear
    @saved_history.each { |h| Reline::HISTORY.push(h) }
  end

  def expand(line)
    capture_stdout { @expanded = @repl.send(:expand_history, line) }
    @expanded
  end

  def test_indirect_variable_expansion_is_not_history
    assert_equal ['echo ${!ref}', false, false], expand('echo ${!ref}')
  end

  def test_array_keys_expansion_is_not_history
    assert_equal ['echo "${!a[@]}" ${!a[*]}', false, false], expand('echo "${!a[@]}" ${!a[*]}')
  end

  def test_prefix_names_expansion_is_not_history
    assert_equal ['echo ${!HOME*}', false, false], expand('echo ${!HOME*}')
  end

  def test_event_designators_still_expand
    assert_equal ['echo previous', true, false], expand('!!')
    assert_equal ['echo previous ${!ref}', true, false], expand('!! ${!ref}')
  end
end
