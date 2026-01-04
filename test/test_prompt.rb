# frozen_string_literal: true

require_relative 'test_helper'

class TestPrompt < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_prompt_test')
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test default prompt (no PS1)
  def test_default_prompt
    ENV.delete('PS1')
    prompt = @repl.send(:prompt)
    assert_match(/\$\s*$/, prompt)
  end

  # Test PS1 with literal text
  def test_ps1_literal_text
    ENV['PS1'] = 'myprompt> '
    prompt = @repl.send(:prompt)
    assert_equal 'myprompt> ', prompt
  end

  # Test \u - username
  def test_ps1_username
    ENV['PS1'] = '\u$ '
    prompt = @repl.send(:prompt)
    expected_user = ENV['USER'] || Etc.getlogin || 'user'
    assert_equal "#{expected_user}$ ", prompt
  end

  # Test \h - short hostname
  def test_ps1_short_hostname
    ENV['PS1'] = '\h$ '
    prompt = @repl.send(:prompt)
    expected_host = Socket.gethostname.split('.').first
    assert_equal "#{expected_host}$ ", prompt
  end

  # Test \H - full hostname
  def test_ps1_full_hostname
    ENV['PS1'] = '\H$ '
    prompt = @repl.send(:prompt)
    expected_host = Socket.gethostname
    assert_equal "#{expected_host}$ ", prompt
  end

  # Test \w - working directory with ~
  def test_ps1_working_directory
    ENV['PS1'] = '\w$ '
    Dir.chdir(ENV['HOME'])
    prompt = @repl.send(:prompt)
    assert_equal '~$ ', prompt
  end

  # Test \W - basename of working directory
  def test_ps1_working_directory_basename
    ENV['PS1'] = '\W$ '
    Dir.chdir(@tempdir)
    prompt = @repl.send(:prompt)
    assert_equal "#{File.basename(@tempdir)}$ ", prompt
  end

  # Test \W for home directory shows ~
  def test_ps1_working_directory_basename_home
    ENV['PS1'] = '\W$ '
    Dir.chdir(ENV['HOME'])
    prompt = @repl.send(:prompt)
    assert_equal '~$ ', prompt
  end

  # Test \$ - $ for regular user
  def test_ps1_dollar_sign
    ENV['PS1'] = '\$ '
    prompt = @repl.send(:prompt)
    # Regular users get $, root gets #
    expected = Process.uid == 0 ? '# ' : '$ '
    assert_equal expected, prompt
  end

  # Test \s - shell name
  def test_ps1_shell_name
    ENV['PS1'] = '\s$ '
    prompt = @repl.send(:prompt)
    assert_equal 'rubish$ ', prompt
  end

  # Test \t - time in 24-hour format
  def test_ps1_time_24hour
    ENV['PS1'] = '\t$ '
    prompt = @repl.send(:prompt)
    assert_match(/^\d{2}:\d{2}:\d{2}\$ $/, prompt)
  end

  # Test \T - time in 12-hour format
  def test_ps1_time_12hour
    ENV['PS1'] = '\T$ '
    prompt = @repl.send(:prompt)
    assert_match(/^\d{2}:\d{2}:\d{2}\$ $/, prompt)
  end

  # Test \A - time in HH:MM format
  def test_ps1_time_short
    ENV['PS1'] = '\A$ '
    prompt = @repl.send(:prompt)
    assert_match(/^\d{2}:\d{2}\$ $/, prompt)
  end

  # Test \@ - time in 12-hour am/pm format
  def test_ps1_time_ampm
    ENV['PS1'] = '\@$ '
    prompt = @repl.send(:prompt)
    assert_match(/^\d{2}:\d{2} [AP]M\$ $/, prompt)
  end

  # Test \d - date
  def test_ps1_date
    ENV['PS1'] = '\d$ '
    prompt = @repl.send(:prompt)
    # Should match "Day Mon DD" format like "Sun Jan 05"
    assert_match(/^[A-Z][a-z]{2} [A-Z][a-z]{2} \d{2}\$ $/, prompt)
  end

  # Test \D{format} - custom date format
  def test_ps1_custom_date_format
    ENV['PS1'] = '\D{%Y-%m-%d}$ '
    prompt = @repl.send(:prompt)
    assert_match(/^\d{4}-\d{2}-\d{2}\$ $/, prompt)
  end

  # Test \v - version
  def test_ps1_version
    ENV['PS1'] = '\v$ '
    prompt = @repl.send(:prompt)
    assert_equal "#{Rubish::VERSION}$ ", prompt
  end

  # Test \n - newline
  def test_ps1_newline
    ENV['PS1'] = 'line1\nline2$ '
    prompt = @repl.send(:prompt)
    assert_equal "line1\nline2$ ", prompt
  end

  # Test \r - carriage return
  def test_ps1_carriage_return
    ENV['PS1'] = 'text\rmore$ '
    prompt = @repl.send(:prompt)
    assert_equal "text\rmore$ ", prompt
  end

  # Test \a - bell
  def test_ps1_bell
    ENV['PS1'] = '\a$ '
    prompt = @repl.send(:prompt)
    assert_equal "\a$ ", prompt
  end

  # Test \e - escape
  def test_ps1_escape
    ENV['PS1'] = '\e[32m$ '
    prompt = @repl.send(:prompt)
    assert_equal "\e[32m$ ", prompt
  end

  # Test \\ - literal backslash
  def test_ps1_backslash
    ENV['PS1'] = '\\\\$ '
    prompt = @repl.send(:prompt)
    assert_equal '\\$ ', prompt
  end

  # Test \[ and \] - non-printing markers (ignored)
  def test_ps1_non_printing_markers
    ENV['PS1'] = '\[\e[32m\]green\[\e[0m\]$ '
    prompt = @repl.send(:prompt)
    assert_equal "\e[32mgreen\e[0m$ ", prompt
  end

  # Test octal character
  def test_ps1_octal_character
    ENV['PS1'] = '\101$ '  # 'A' in octal
    prompt = @repl.send(:prompt)
    assert_equal 'A$ ', prompt
  end

  # Test \j - number of jobs
  def test_ps1_job_count
    ENV['PS1'] = '[\j]$ '
    prompt = @repl.send(:prompt)
    # Should be 0 jobs by default
    assert_equal '[0]$ ', prompt
  end

  # Test \! - history number
  def test_ps1_history_number
    ENV['PS1'] = '!\!$ '
    prompt = @repl.send(:prompt)
    assert_match(/^!\d+\$ $/, prompt)
  end

  # Test \# - command number
  def test_ps1_command_number
    ENV['PS1'] = '#\#$ '
    prompt = @repl.send(:prompt)
    assert_equal '#1$ ', prompt
  end

  # Test combined escape sequences
  def test_ps1_combined
    ENV['PS1'] = '\u@\h:\w\$ '
    Dir.chdir(ENV['HOME'])
    prompt = @repl.send(:prompt)
    expected_user = ENV['USER'] || Etc.getlogin || 'user'
    expected_host = Socket.gethostname.split('.').first
    expected = "#{expected_user}@#{expected_host}:~$ "
    assert_equal expected, prompt
  end

  # Test PS2 default
  def test_ps2_default
    ENV.delete('PS2')
    prompt = @repl.send(:continuation_prompt)
    assert_equal '> ', prompt
  end

  # Test PS2 custom
  def test_ps2_custom
    ENV['PS2'] = '... '
    prompt = @repl.send(:continuation_prompt)
    assert_equal '... ', prompt
  end

  # Test PS2 with escapes
  def test_ps2_with_escapes
    ENV['PS2'] = '\s> '
    prompt = @repl.send(:continuation_prompt)
    assert_equal 'rubish> ', prompt
  end

  # Test unknown escape keeps literal
  def test_ps1_unknown_escape
    ENV['PS1'] = '\x$ '
    prompt = @repl.send(:prompt)
    assert_equal '\\x$ ', prompt
  end

  # Test colored prompt example
  def test_ps1_color_example
    ENV['PS1'] = '\[\e[32m\]\u\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\$ '
    prompt = @repl.send(:prompt)
    # Should contain ANSI escape codes
    assert_match(/\e\[32m/, prompt)
    assert_match(/\e\[0m/, prompt)
    assert_match(/\e\[34m/, prompt)
  end

  # PS4 tests (xtrace debugging prompt)
  def test_ps4_default
    ENV.delete('PS4')
    output = capture_stderr do
      @repl.send(:xtrace, 'echo hello')
    end
    assert_equal "+ echo hello\n", output
  end

  def test_ps4_custom
    ENV['PS4'] = '>>> '
    output = capture_stderr do
      @repl.send(:xtrace, 'echo hello')
    end
    assert_equal ">>> echo hello\n", output
  end

  def test_ps4_with_escapes
    ENV['PS4'] = '[\t] + '
    output = capture_stderr do
      @repl.send(:xtrace, 'echo hello')
    end
    # Should expand \t to time
    assert_match(/^\[\d{2}:\d{2}:\d{2}\] \+ echo hello$/, output.strip)
  end

  def test_ps4_with_shell_name
    ENV['PS4'] = '\s: '
    output = capture_stderr do
      @repl.send(:xtrace, 'ls')
    end
    assert_equal "rubish: ls\n", output
  end

  def test_ps4_with_command_number
    ENV['PS4'] = '+(\#) '
    output = capture_stderr do
      @repl.send(:xtrace, 'echo test')
    end
    assert_match(/^\+\(\d+\) echo test$/, output.strip)
  end

  def test_ps4_integration_with_set_x
    ENV['PS4'] = '+ '
    # Enable xtrace
    Rubish::Builtins.run('set', ['-x'])

    output = capture_stderr do
      @repl.send(:execute, 'true')
    end

    # Disable xtrace
    Rubish::Builtins.run('set', ['+x'])

    assert_match(/^\+ true$/, output.strip)
  end
end
