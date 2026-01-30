# frozen_string_literal: true

require_relative 'test_helper'

class TestLithist < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_lithist_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    # Clear history
    Reline::HISTORY.clear
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
    Reline::HISTORY.clear
  end

  def update_history_with_heredoc(command_line, delimiter, heredoc_content)
    @repl.send(:update_history_with_heredoc, command_line, delimiter, heredoc_content)
  end

  # lithist is disabled by default
  def test_lithist_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('lithist')
  end

  def test_lithist_can_be_enabled
    execute('shopt -s lithist')
    assert Rubish::Builtins.shopt_enabled?('lithist')
  end

  def test_lithist_can_be_disabled
    execute('shopt -s lithist')
    execute('shopt -u lithist')
    assert_false Rubish::Builtins.shopt_enabled?('lithist')
  end

  # cmdhist is enabled by default
  def test_cmdhist_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('cmdhist')
  end

  # Test update_history_with_heredoc without lithist
  def test_heredoc_history_without_lithist_semicolon_format
    # Add initial entry
    Reline::HISTORY << 'cat <<EOF'

    # Call update with heredoc content
    update_history_with_heredoc('cat <<EOF', 'EOF', "line1\nline2\n")

    # Last entry should have semicolons instead of newlines
    last_entry = Reline::HISTORY.to_a.last
    assert_equal 'cat <<EOF line1; line2; EOF', last_entry
  end

  def test_heredoc_history_without_lithist_single_line
    # Add initial entry
    Reline::HISTORY << 'cat <<EOF'

    # Call update with single line content
    update_history_with_heredoc('cat <<EOF', 'EOF', "single\n")

    last_entry = Reline::HISTORY.to_a.last
    assert_equal 'cat <<EOF single; EOF', last_entry
  end

  def test_heredoc_history_without_lithist_empty_content
    # Add initial entry
    Reline::HISTORY << 'cat <<EOF'

    # Call update with empty content
    update_history_with_heredoc('cat <<EOF', 'EOF', '')

    last_entry = Reline::HISTORY.to_a.last
    assert_equal 'cat <<EOF ; EOF', last_entry
  end

  # Test update_history_with_heredoc with lithist
  def test_heredoc_history_with_lithist_preserves_newlines
    execute('shopt -s lithist')

    # Add initial entry
    Reline::HISTORY << 'cat <<EOF'

    # Call update with heredoc content
    update_history_with_heredoc('cat <<EOF', 'EOF', "line1\nline2\n")

    # Last entry should preserve newlines
    last_entry = Reline::HISTORY.to_a.last
    expected = "cat <<EOF\nline1\nline2\nEOF"
    assert_equal expected, last_entry
  end

  def test_heredoc_history_with_lithist_single_line
    execute('shopt -s lithist')

    # Add initial entry
    Reline::HISTORY << 'cat <<EOF'

    update_history_with_heredoc('cat <<EOF', 'EOF', "single\n")

    last_entry = Reline::HISTORY.to_a.last
    expected = "cat <<EOF\nsingle\nEOF"
    assert_equal expected, last_entry
  end

  # Test that cmdhist must be enabled
  def test_no_update_when_cmdhist_disabled
    execute('shopt -u cmdhist')

    # Add initial entry
    Reline::HISTORY << 'cat <<EOF'

    # Call update - should do nothing since cmdhist is disabled
    update_history_with_heredoc('cat <<EOF', 'EOF', "line1\nline2\n")

    # Entry should be unchanged
    last_entry = Reline::HISTORY.to_a.last
    assert_equal 'cat <<EOF', last_entry
  end

  def test_no_update_when_history_empty
    # Ensure history is empty
    Reline::HISTORY.clear

    # Should not raise error
    update_history_with_heredoc('cat <<EOF', 'EOF', "content\n")

    # History should still be empty
    assert_equal 0, Reline::HISTORY.size
  end

  # Test toggling lithist
  def test_toggle_lithist
    # Initially disabled
    assert_false Rubish::Builtins.shopt_enabled?('lithist')

    # Enable
    execute('shopt -s lithist')
    assert Rubish::Builtins.shopt_enabled?('lithist')

    # Disable
    execute('shopt -u lithist')
    assert_false Rubish::Builtins.shopt_enabled?('lithist')

    # Enable again
    execute('shopt -s lithist')
    assert Rubish::Builtins.shopt_enabled?('lithist')
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt lithist')
    end
    assert_match(/lithist/, output)
    assert_match(/off/, output)

    execute('shopt -s lithist')

    output = capture_output do
      execute('shopt lithist')
    end
    assert_match(/lithist/, output)
    assert_match(/on/, output)
  end

  # Test with different heredoc delimiters
  def test_heredoc_with_custom_delimiter
    Reline::HISTORY << 'cat <<DELIM'
    update_history_with_heredoc('cat <<DELIM', 'DELIM', "content\n")

    last_entry = Reline::HISTORY.to_a.last
    assert_equal 'cat <<DELIM content; DELIM', last_entry
  end

  def test_heredoc_with_custom_delimiter_lithist
    execute('shopt -s lithist')

    Reline::HISTORY << 'cat <<MYDELIM'
    update_history_with_heredoc('cat <<MYDELIM', 'MYDELIM', "content\n")

    last_entry = Reline::HISTORY.to_a.last
    expected = "cat <<MYDELIM\ncontent\nMYDELIM"
    assert_equal expected, last_entry
  end

  # Test with multiple lines
  def test_heredoc_multiple_lines
    Reline::HISTORY << 'cat <<EOF'
    update_history_with_heredoc('cat <<EOF', 'EOF', "line1\nline2\nline3\nline4\n")

    last_entry = Reline::HISTORY.to_a.last
    assert_equal 'cat <<EOF line1; line2; line3; line4; EOF', last_entry
  end

  def test_heredoc_multiple_lines_lithist
    execute('shopt -s lithist')

    Reline::HISTORY << 'cat <<EOF'
    update_history_with_heredoc('cat <<EOF', 'EOF', "line1\nline2\nline3\n")

    last_entry = Reline::HISTORY.to_a.last
    expected = "cat <<EOF\nline1\nline2\nline3\nEOF"
    assert_equal expected, last_entry
  end
end
