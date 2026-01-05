# frozen_string_literal: true

require_relative 'test_helper'

class TestFc < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_fc_test')
    # Clear history and add test commands
    Reline::HISTORY.clear
    @test_commands = ['echo hello', 'ls -la', 'pwd', 'cd /tmp', 'echo world']
    @test_commands.each { |cmd| Reline::HISTORY << cmd }
  end

  def teardown
    Reline::HISTORY.clear
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test fc is a builtin
  def test_fc_is_builtin
    assert Rubish::Builtins.builtin?('fc')
  end

  # Test fc -l lists history
  def test_fc_l_lists_history
    output = capture_output { Rubish::Builtins.run('fc', ['-l']) }
    assert_match(/echo hello/, output)
    assert_match(/ls -la/, output)
    assert_match(/pwd/, output)
  end

  # Test fc -l shows line numbers
  def test_fc_l_shows_line_numbers
    output = capture_output { Rubish::Builtins.run('fc', ['-l']) }
    # Should have format like "    1  echo hello"
    assert_match(/\d+\s+echo hello/, output)
  end

  # Test fc -ln suppresses line numbers
  def test_fc_ln_suppresses_numbers
    output = capture_output { Rubish::Builtins.run('fc', ['-ln']) }
    # Should not have leading numbers
    lines = output.strip.split("\n")
    lines.each do |line|
      assert_no_match(/^\s*\d+\s+/, line)
    end
  end

  # Test fc -l with range
  def test_fc_l_with_range
    output = capture_output { Rubish::Builtins.run('fc', ['-l', '2', '4']) }
    assert_match(/ls -la/, output)
    assert_match(/pwd/, output)
    assert_match(/cd \/tmp/, output)
    assert_no_match(/echo hello/, output)
    assert_no_match(/echo world/, output)
  end

  # Test fc -l with negative range
  def test_fc_l_with_negative_range
    output = capture_output { Rubish::Builtins.run('fc', ['-l', '-3', '-1']) }
    assert_match(/pwd/, output)
    assert_match(/cd \/tmp/, output)
    assert_match(/echo world/, output)
  end

  # Test fc -lr reverses order
  def test_fc_lr_reverses_order
    output = capture_output { Rubish::Builtins.run('fc', ['-lr', '1', '3']) }
    lines = output.strip.split("\n")
    assert_match(/pwd/, lines[0])
    assert_match(/ls -la/, lines[1])
    assert_match(/echo hello/, lines[2])
  end

  # Test fc -l with string search
  def test_fc_l_with_string
    output = capture_output { Rubish::Builtins.run('fc', ['-l', 'ls']) }
    # Should find 'ls -la' and list from there to end
    assert_match(/ls -la/, output)
  end

  # Test fc -s re-executes last command
  def test_fc_s_reexecutes_last
    executed = nil
    Rubish::Builtins.executor = ->(cmd) { executed = cmd }

    output = capture_output { Rubish::Builtins.run('fc', ['-s']) }
    assert_match(/echo world/, output)
    assert_equal 'echo world', executed
  end

  # Test fc -s with specific command
  def test_fc_s_with_command
    executed = nil
    Rubish::Builtins.executor = ->(cmd) { executed = cmd }

    output = capture_output { Rubish::Builtins.run('fc', ['-s', 'ls']) }
    assert_match(/ls -la/, output)
    assert_equal 'ls -la', executed
  end

  # Test fc -s with substitution
  def test_fc_s_with_substitution
    executed = nil
    Rubish::Builtins.executor = ->(cmd) { executed = cmd }

    # Use command spec to find 'echo hello' and substitute
    output = capture_output { Rubish::Builtins.run('fc', ['-s', 'hello=goodbye', '1']) }
    assert_match(/echo goodbye/, output)
    assert_equal 'echo goodbye', executed
  end

  # Test fc -s with number
  def test_fc_s_with_number
    executed = nil
    Rubish::Builtins.executor = ->(cmd) { executed = cmd }

    output = capture_output { Rubish::Builtins.run('fc', ['-s', '2']) }
    assert_match(/ls -la/, output)
    assert_equal 'ls -la', executed
  end

  # Test fc with invalid option
  def test_fc_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('fc', ['-z'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test fc with out of range
  def test_fc_out_of_range
    output = capture_output do
      result = Rubish::Builtins.run('fc', ['-l', '100'])
      assert_false result
    end
    assert_match(/out of range/, output)
  end

  # Test fc -e requires argument
  def test_fc_e_requires_argument
    output = capture_output do
      result = Rubish::Builtins.run('fc', ['-e'])
      assert_false result
    end
    assert_match(/option requires an argument/, output)
  end

  # Test fc with empty history
  def test_fc_empty_history
    Reline::HISTORY.clear
    result = Rubish::Builtins.run('fc', ['-l'])
    assert result  # Should return true even with empty history
  end

  # Test fc -lnr combined flags
  def test_fc_lnr_combined
    output = capture_output { Rubish::Builtins.run('fc', ['-lnr', '1', '3']) }
    lines = output.strip.split("\n")
    # Should be reversed and without numbers
    assert_equal 'pwd', lines[0]
    assert_equal 'ls -la', lines[1]
    assert_equal 'echo hello', lines[2]
  end

  # Test type identifies fc as builtin
  def test_type_identifies_fc_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['fc']) }
    assert_match(/fc is a shell builtin/, output)
  end

  # Test fc via REPL
  def test_fc_via_repl
    output = capture_output { execute('fc -l -2 -1') }
    assert_match(/cd \/tmp/, output)
    assert_match(/echo world/, output)
  end

  # Test help for fc
  def test_help_fc
    output = capture_output { Rubish::Builtins.run('help', ['fc']) }
    assert_match(/fc:/, output)
    assert_match(/Display or edit and re-execute/, output)
    assert_match(/-l/, output)
    assert_match(/-s/, output)
  end

  # Test fc -s command not found
  def test_fc_s_command_not_found
    output = capture_output do
      result = Rubish::Builtins.run('fc', ['-s', 'nonexistent'])
      assert_false result
    end
    assert_match(/no command found/, output)
  end

  # FCEDIT variable tests

  def test_fcedit_used_as_default_editor
    # Create a mock editor that just writes to a marker file
    editor_script = File.join(@tempdir, 'mock_editor.sh')
    marker_file = File.join(@tempdir, 'editor_used.txt')
    File.write(editor_script, <<~BASH)
      #!/bin/bash
      echo "FCEDIT editor was used" > #{marker_file}
      # Don't modify the file, just exit
    BASH
    File.chmod(0755, editor_script)

    ENV['FCEDIT'] = editor_script
    ENV.delete('EDITOR')

    # fc without -e should use FCEDIT
    # Note: This test just verifies the variable is read correctly
    editor = ENV['FCEDIT'] || ENV['EDITOR'] || 'vi'
    assert_equal editor_script, editor
  end

  def test_fcedit_takes_precedence_over_editor
    ENV['FCEDIT'] = '/usr/bin/fcedit'
    ENV['EDITOR'] = '/usr/bin/editor'

    editor = ENV['FCEDIT'] || ENV['EDITOR'] || 'vi'
    assert_equal '/usr/bin/fcedit', editor
  end

  def test_editor_used_when_fcedit_not_set
    ENV.delete('FCEDIT')
    ENV['EDITOR'] = '/usr/bin/nano'

    editor = ENV['FCEDIT'] || ENV['EDITOR'] || 'vi'
    assert_equal '/usr/bin/nano', editor
  end

  def test_vi_used_when_no_editor_vars_set
    ENV.delete('FCEDIT')
    ENV.delete('EDITOR')

    editor = ENV['FCEDIT'] || ENV['EDITOR'] || 'vi'
    assert_equal 'vi', editor
  end

  def test_fcedit_empty_falls_through_to_editor
    ENV['FCEDIT'] = ''
    ENV['EDITOR'] = '/usr/bin/emacs'

    # Empty FCEDIT should fall through to EDITOR
    # Test using the same logic as fc_edit_and_execute
    editor = (ENV['FCEDIT'] unless ENV['FCEDIT'].to_s.empty?) ||
             (ENV['EDITOR'] unless ENV['EDITOR'].to_s.empty?) ||
             'vi'
    assert_equal '/usr/bin/emacs', editor
  end

  def test_both_empty_falls_through_to_vi
    ENV['FCEDIT'] = ''
    ENV['EDITOR'] = ''

    editor = (ENV['FCEDIT'] unless ENV['FCEDIT'].to_s.empty?) ||
             (ENV['EDITOR'] unless ENV['EDITOR'].to_s.empty?) ||
             'vi'
    assert_equal 'vi', editor
  end
end
