# frozen_string_literal: true

require_relative 'test_helper'

class TestVariableCompletion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.clear_shell_vars
  end

  # Test basic environment variable completion
  def test_complete_env_var_path
    results = @repl.send(:complete_variable, '$PA')
    assert_kind_of Array, results
    assert results.include?('$PATH'), 'Should complete $PA to $PATH'
  end

  def test_complete_env_var_home
    results = @repl.send(:complete_variable, '$HO')
    assert_kind_of Array, results
    assert results.include?('$HOME'), 'Should complete $HO to $HOME'
  end

  # Test completion with braces ${VAR}
  def test_complete_env_var_with_braces
    results = @repl.send(:complete_variable, '${PA')
    assert_kind_of Array, results
    assert results.include?('${PATH}'), "Should complete \${PA to \${PATH}"
  end

  def test_complete_env_var_with_braces_home
    results = @repl.send(:complete_variable, '${HO')
    assert_kind_of Array, results
    assert results.include?('${HOME}'), "Should complete \${HO to \${HOME}"
  end

  # Test shell variable completion (non-ENV variables)
  def test_complete_shell_var
    Rubish::Builtins.set_var('MY_SHELL_VAR', 'test_value')
    results = @repl.send(:complete_variable, '$MY_SH')
    assert_kind_of Array, results
    assert results.include?('$MY_SHELL_VAR'), 'Should complete $MY_SH to $MY_SHELL_VAR'
  end

  # Test completion with no matches
  def test_complete_var_no_match
    results = @repl.send(:complete_variable, '$ZZZNONEXISTENT')
    assert_kind_of Array, results
    assert results.empty?, 'Should return empty array for no matches'
  end

  # Test completion shows all vars with just $
  def test_complete_all_vars
    results = @repl.send(:complete_variable, '$')
    assert_kind_of Array, results
    assert results.length > 0, 'Should return multiple variables'
    assert results.include?('$PATH'), 'Should include $PATH'
    assert results.include?('$HOME'), 'Should include $HOME'
  end

  # Test that complete_variable is called for $ prefix
  # (We test complete_variable directly since complete() requires Reline state)
  def test_complete_variable_called_for_dollar_prefix
    # Verify that complete_variable handles $ prefixed input correctly
    results = @repl.send(:complete_variable, '$PATH')
    assert results.include?('$PATH'), 'Should complete exact match'
  end

  # Test results are sorted
  def test_complete_var_sorted
    ENV['AAA_TEST'] = '1'
    ENV['AAB_TEST'] = '2'
    ENV['AAC_TEST'] = '3'
    results = @repl.send(:complete_variable, '$AA')
    assert_equal results, results.sort, 'Results should be sorted'
  ensure
    ENV.delete('AAA_TEST')
    ENV.delete('AAB_TEST')
    ENV.delete('AAC_TEST')
  end

  # Test no duplicates between ENV and shell_vars
  def test_complete_var_no_duplicates
    # Set same var in both ENV and shell_vars
    ENV['DUP_TEST_VAR'] = 'env_value'
    Rubish::Builtins.set_var('DUP_TEST_VAR', 'shell_value')

    results = @repl.send(:complete_variable, '$DUP_TEST')
    dup_count = results.count { |r| r == '$DUP_TEST_VAR' }
    assert_equal 1, dup_count, 'Should not have duplicate completions'
  ensure
    ENV.delete('DUP_TEST_VAR')
  end

  # Test that complete() detects ${...} context from line buffer
  # When user types "${PA", Reline splits on { and passes just "PA"
  # We return "PATH}" so Reline replaces "PA" -> "PATH}" giving "${PATH}"
  def test_complete_detects_brace_context
    # Temporarily replace Reline methods
    original_line_buffer = Reline.method(:line_buffer) rescue nil
    original_point = Reline.method(:point) rescue nil

    Reline.define_singleton_method(:line_buffer) { '${PA' }
    Reline.define_singleton_method(:point) { 4 }

    begin
      results = @repl.send(:complete, 'PA')
      # We return "PATH}" (not "${PATH}") because Reline replaces just "PA"
      assert results.include?('PATH}'), 'Should return PATH} so Reline makes ${PATH}'
    ensure
      # Restore original methods if they existed
      if original_line_buffer
        Reline.define_singleton_method(:line_buffer, original_line_buffer)
      end
      if original_point
        Reline.define_singleton_method(:point, original_point)
      end
    end
  end
end
