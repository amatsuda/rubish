# frozen_string_literal: true

require_relative 'test_helper'

class TestConditionalPattern < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    # Ensure clean state
    Rubish::Builtins.run('shopt', ['-u', 'extglob'])
    Rubish::Builtins.run('shopt', ['-u', 'nocasematch'])
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    # Reset shopts to default
    Rubish::Builtins.run('shopt', ['-u', 'extglob'])
    Rubish::Builtins.run('shopt', ['-u', 'nocasematch'])
  end

  def execute(cmd)
    @repl.send(:execute, cmd)
    @repl.instance_variable_get(:@last_status)
  end

  # Basic glob pattern tests
  def test_pattern_prefix_wildcard
    assert_equal 0, execute('[[ hello == hel* ]]')
  end

  def test_pattern_suffix_wildcard
    assert_equal 0, execute('[[ hello == *llo ]]')
  end

  def test_pattern_middle_wildcard
    assert_equal 0, execute('[[ hello == *ell* ]]')
  end

  def test_pattern_single_char_wildcard
    assert_equal 0, execute('[[ hello == h?llo ]]')
  end

  def test_pattern_exact_match
    assert_equal 0, execute('[[ hello == hello ]]')
  end

  def test_pattern_no_match
    assert_equal 1, execute('[[ hello == world ]]')
  end

  def test_pattern_extension_match
    assert_equal 0, execute('[[ file.txt == *.txt ]]')
  end

  def test_pattern_extension_no_match
    assert_equal 1, execute('[[ file.txt == *.doc ]]')
  end

  def test_pattern_character_class
    assert_equal 0, execute('[[ abc123 == [a-z]* ]]')
  end

  def test_pattern_character_class_no_match
    assert_equal 1, execute('[[ 123abc == [a-z]* ]]')
  end

  def test_pattern_not_equal
    assert_equal 0, execute('[[ hello != world ]]')
  end

  def test_pattern_not_equal_fails
    assert_equal 1, execute('[[ hello != hello ]]')
  end

  # Extglob pattern tests (require shopt -s extglob)
  def test_extglob_at_match
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 0, execute('[[ foo.c == *.@(c|h) ]]')
  end

  def test_extglob_at_match_alt
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 0, execute('[[ foo.h == *.@(c|h) ]]')
  end

  def test_extglob_at_no_match
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 1, execute('[[ foo.o == *.@(c|h) ]]')
  end

  def test_extglob_question_one
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 0, execute('[[ foobar == foo?(bar) ]]')
  end

  def test_extglob_question_zero
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 0, execute('[[ foo == foo?(bar) ]]')
  end

  def test_extglob_question_no_match
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 1, execute('[[ foobarbar == foo?(bar) ]]')
  end

  def test_extglob_star_one
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 0, execute('[[ foobar == foo*(bar) ]]')
  end

  def test_extglob_star_multiple
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 0, execute('[[ foobarbar == foo*(bar) ]]')
  end

  def test_extglob_star_zero
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 0, execute('[[ foo == foo*(bar) ]]')
  end

  def test_extglob_plus_one
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 0, execute('[[ foobar == foo+(bar) ]]')
  end

  def test_extglob_plus_multiple
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 0, execute('[[ foobarbar == foo+(bar) ]]')
  end

  def test_extglob_plus_zero_no_match
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 1, execute('[[ foo == foo+(bar) ]]')
  end

  def test_extglob_negation_match
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 0, execute('[[ hello == !(world) ]]')
  end

  def test_extglob_negation_no_match
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    assert_equal 1, execute('[[ world == !(world) ]]')
  end

  # Test extglob disabled (patterns should be literal)
  def test_extglob_disabled_at_literal
    Rubish::Builtins.run('shopt', ['-u', 'extglob'])
    # Without extglob, @(c|h) is not a special pattern
    assert_equal 1, execute('[[ foo.c == *.@(c|h) ]]')
  end

  # Test with variables
  def test_pattern_with_variable
    ENV['MYVAR'] = 'hello'
    assert_equal 0, execute('[[ $MYVAR == hel* ]]')
  end

  def test_extglob_with_variable
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    ENV['MYVAR'] = 'foo.c'
    assert_equal 0, execute('[[ $MYVAR == *.@(c|h) ]]')
  end

  # Test nocasematch
  def test_pattern_case_sensitive
    assert_equal 1, execute('[[ HELLO == hello ]]')
  end

  def test_pattern_nocasematch
    Rubish::Builtins.run('shopt', ['-s', 'nocasematch'])
    assert_equal 0, execute('[[ HELLO == hello ]]')
    Rubish::Builtins.run('shopt', ['-u', 'nocasematch'])
  end

  def test_extglob_nocasematch
    Rubish::Builtins.run('shopt', ['-s', 'extglob'])
    Rubish::Builtins.run('shopt', ['-s', 'nocasematch'])
    assert_equal 0, execute('[[ FOO.C == *.@(c|h) ]]')
    Rubish::Builtins.run('shopt', ['-u', 'nocasematch'])
  end

  # Test reconstruct_glob_pattern helper
  def test_reconstruct_glob_pattern_simple
    result = @repl.send(:reconstruct_glob_pattern, ['*.txt'])
    assert_equal '*.txt', result
  end

  def test_reconstruct_glob_pattern_extglob
    result = @repl.send(:reconstruct_glob_pattern, ['*.@', '(', 'c', '|', 'h', ')'])
    assert_equal '*.@(c|h)', result
  end

  def test_reconstruct_glob_pattern_complex
    result = @repl.send(:reconstruct_glob_pattern, ['foo', '?', '(', 'bar', '|', 'baz', ')'])
    assert_equal 'foo ?(bar|baz)', result
  end
end
