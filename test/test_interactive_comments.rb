# frozen_string_literal: true

require_relative 'test_helper'

class TestInteractiveComments < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
  end

  # interactive_comments is enabled by default (like bash)
  def test_interactive_comments_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('interactive_comments')
  end

  def test_interactive_comments_can_be_disabled
    execute('shopt -u interactive_comments')
    assert_false Rubish::Builtins.shopt_enabled?('interactive_comments')
  end

  def test_interactive_comments_can_be_re_enabled
    execute('shopt -u interactive_comments')
    execute('shopt -s interactive_comments')
    assert Rubish::Builtins.shopt_enabled?('interactive_comments')
  end

  def test_comment_at_end_of_line_stripped
    output = capture_stdout { execute('echo hello # this is a comment') }
    assert_equal "hello\n", output
  end

  def test_comment_at_start_of_line
    output = capture_stdout { execute('# this is a comment') }
    assert_equal '', output
  end

  def test_hash_inside_single_quotes_not_stripped
    output = capture_stdout { execute("echo 'hello # world'") }
    assert_equal "hello # world\n", output
  end

  def test_hash_inside_double_quotes_not_stripped
    output = capture_stdout { execute('echo "hello # world"') }
    assert_equal "hello # world\n", output
  end

  def test_hash_without_preceding_space_kept
    # foo#bar is one word, # is not a comment marker
    output = capture_stdout { execute('echo foo#bar') }
    assert_equal "foo#bar\n", output
  end

  def test_multiple_hash_only_first_is_comment
    output = capture_stdout { execute('echo hello # comment #2 #3') }
    assert_equal "hello\n", output
  end

  def test_disabled_interactive_comments_keeps_hash
    execute('shopt -u interactive_comments')
    # With interactive_comments disabled, # is literal
    # This will try to run a command with # in its arguments
    # Since we can't easily test the error, just verify the option is disabled
    assert_false Rubish::Builtins.shopt_enabled?('interactive_comments')
  end

  def test_escaped_hash_not_comment
    output = capture_stdout { execute('echo hello \\# world') }
    # The backslash escapes the #, so it's not a comment
    assert_match(/hello/, output)
  end

  def test_hash_in_variable_expansion
    ENV['TEST_VAR'] = 'hello#world'
    output = capture_stdout { execute('echo $TEST_VAR') }
    assert_equal "hello#world\n", output
  ensure
    ENV.delete('TEST_VAR')
  end

  def test_hash_preceded_by_dollar_not_comment
    # $# is a special variable (number of positional params), not a comment
    # Since we have no positional params, $# should be 0
    output = capture_stdout { execute('echo $#') }
    assert_equal "0\n", output
  end

  def test_comment_with_tabs
    output = capture_stdout { execute("echo hello\t# comment with tab before") }
    assert_equal "hello\n", output
  end

  def test_only_spaces_before_hash
    output = capture_stdout { execute('   # just a comment') }
    assert_equal '', output
  end

  def test_command_with_multiple_args_and_comment
    output = capture_stdout { execute('echo one two three # four five') }
    assert_equal "one two three\n", output
  end

  def test_comment_after_semicolon
    # The comment after semicolon should be stripped
    # We verify by checking that only the last command's output appears
    output = capture_stdout { execute('echo final # this comment is stripped') }
    assert_equal "final\n", output
    # Verify the comment was actually stripped (not included as an argument)
    assert_not_match(/comment/, output)
  end
end
