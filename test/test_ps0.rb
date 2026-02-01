# frozen_string_literal: true

require_relative 'test_helper'

class TestPS0 < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_ps0_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic PS0 functionality

  def test_ps0_not_printed_when_unset
    ENV.delete('PS0')
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal '', output
  end

  def test_ps0_not_printed_when_empty
    ENV['PS0'] = ''
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal '', output
  end

  def test_ps0_literal_text
    ENV['PS0'] = 'EXECUTING: '
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal 'EXECUTING: ', output
  end

  def test_ps0_with_newline
    ENV['PS0'] = "Running...\n"
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal "Running...\n", output
  end

  # Test escape sequences (same as PS1)

  def test_ps0_username
    ENV['PS0'] = '\u> '
    output = capture_stdout { @repl.send(:print_ps0) }
    expected_user = ENV['USER'] || Etc.getlogin || 'user'
    assert_equal "#{expected_user}> ", output
  end

  def test_ps0_hostname
    ENV['PS0'] = '\h: '
    output = capture_stdout { @repl.send(:print_ps0) }
    expected_host = Socket.gethostname.split('.').first
    assert_equal "#{expected_host}: ", output
  end

  def test_ps0_full_hostname
    ENV['PS0'] = '\H: '
    output = capture_stdout { @repl.send(:print_ps0) }
    expected_host = Socket.gethostname
    assert_equal "#{expected_host}: ", output
  end

  def test_ps0_working_directory
    ENV['PS0'] = '\w> '
    Dir.chdir(ENV['HOME'])
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal '~> ', output
  end

  def test_ps0_working_directory_basename
    ENV['PS0'] = '\W> '
    Dir.chdir(@tempdir)
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal "#{File.basename(@tempdir)}> ", output
  end

  def test_ps0_shell_name
    ENV['PS0'] = '\s: '
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal 'rubish: ', output
  end

  def test_ps0_time_24hr
    ENV['PS0'] = '[\t] '
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_match(/^\[\d{2}:\d{2}:\d{2}\] $/, output)
  end

  def test_ps0_time_24hr_short
    ENV['PS0'] = '[\A] '
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_match(/^\[\d{2}:\d{2}\] $/, output)
  end

  def test_ps0_date
    ENV['PS0'] = '\d: '
    output = capture_stdout { @repl.send(:print_ps0) }
    # Should match format like "Mon Jan 05: "
    assert_match(/^[A-Z][a-z]{2} [A-Z][a-z]{2} \d{2}: $/, output)
  end

  def test_ps0_custom_date_format
    ENV['PS0'] = '\D{%Y-%m-%d}: '
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_match(/^\d{4}-\d{2}-\d{2}: $/, output)
  end

  def test_ps0_newline_escape
    ENV['PS0'] = "line1\nline2: "
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal "line1\nline2: ", output
  end

  def test_ps0_bell
    ENV['PS0'] = '\a: '
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal "\a: ", output
  end

  def test_ps0_escape_character
    ENV['PS0'] = '\e[32m> '
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal "\e[32m> ", output
  end

  def test_ps0_literal_backslash
    ENV['PS0'] = '\\\\> '
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal '\\> ', output
  end

  def test_ps0_dollar_sign
    ENV['PS0'] = '\$ '
    output = capture_stdout { @repl.send(:print_ps0) }
    # $ for non-root, # for root
    expected = Process.uid == 0 ? '# ' : '$ '
    assert_equal expected, output
  end

  def test_ps0_history_number
    ENV['PS0'] = '!\!: '
    output = capture_stdout { @repl.send(:print_ps0) }
    # Should contain a number
    assert_match(/^!\d+: $/, output)
  end

  def test_ps0_command_number
    ENV['PS0'] = '#\#: '
    output = capture_stdout { @repl.send(:print_ps0) }
    # Should contain a number
    assert_match(/^#\d+: $/, output)
  end

  def test_ps0_version
    ENV['PS0'] = '\v: '
    output = capture_stdout { @repl.send(:print_ps0) }
    # Version can be x.y or x.y.z format
    assert_match(/^\d+\.\d+(\.\d+)?: $/, output)
  end

  def test_ps0_jobs_count
    ENV['PS0'] = '[\j] '
    output = capture_stdout { @repl.send(:print_ps0) }
    # Jobs count should be a number
    assert_match(/^\[\d+\] $/, output)
  end

  def test_ps0_octal_character
    ENV['PS0'] = '\101: '  # 'A' in octal
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal 'A: ', output
  end

  # Combined usage

  def test_ps0_combined_escapes
    ENV['PS0'] = '[\t] \u@\h: '
    output = capture_stdout { @repl.send(:print_ps0) }
    expected_user = ENV['USER'] || Etc.getlogin || 'user'
    expected_host = Socket.gethostname.split('.').first
    assert_match(/^\[\d{2}:\d{2}:\d{2}\] #{Regexp.escape(expected_user)}@#{Regexp.escape(expected_host)}: $/, output)
  end

  def test_ps0_with_colors
    ENV['PS0'] = '\[\e[32m\]Running\[\e[0m\]: '
    output = capture_stdout { @repl.send(:print_ps0) }
    # \[ and \] are ignored for length calculation but should be stripped
    assert_equal "\e[32mRunning\e[0m: ", output
  end

  # Variable tests

  def test_ps0_can_be_set
    execute('PS0=">>> "')
    assert_equal '>>> ', Rubish::Builtins.get_var('PS0')
  end

  def test_ps0_can_be_read
    ENV['PS0'] = 'test'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $PS0 > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'test', value
  end

  def test_ps0_can_be_unset
    ENV['PS0'] = 'test'
    execute('unset PS0')
    assert_nil ENV['PS0']
  end

  def test_ps0_can_be_exported
    execute('PS0="running: "')
    execute('export PS0')
    assert_equal 'running: ', ENV['PS0']
  end

  # Edge cases

  def test_ps0_unknown_escape
    ENV['PS0'] = '\x: '
    output = capture_stdout { @repl.send(:print_ps0) }
    # Unknown escapes should be preserved as-is
    assert_equal '\x: ', output
  end

  def test_ps0_trailing_backslash
    # A trailing backslash without following character is consumed
    ENV['PS0'] = 'test\\\\'  # Two backslashes in Ruby = one literal backslash
    output = capture_stdout { @repl.send(:print_ps0) }
    assert_equal 'test\\', output
  end
end
