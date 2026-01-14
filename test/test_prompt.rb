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
    # Disable promptvars to test bash escape processing only
    # With promptvars enabled, \$ would be further processed as escaped $
    Rubish::Builtins.shell_options['promptvars'] = false
    ENV['PS1'] = '\\\\$ '
    prompt = @repl.send(:prompt)
    assert_equal '\\$ ', prompt
  ensure
    Rubish::Builtins.shell_options['promptvars'] = true
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

  # PS3 tests (select menu prompt)
  def test_ps3_default
    ENV.delete('PS3')
    prompt = @repl.send(:select_prompt)
    assert_equal '#? ', prompt
  end

  def test_ps3_custom
    ENV['PS3'] = 'Choose: '
    prompt = @repl.send(:select_prompt)
    assert_equal 'Choose: ', prompt
  end

  def test_ps3_with_escapes
    ENV['PS3'] = '[\s] Select: '
    prompt = @repl.send(:select_prompt)
    assert_equal '[rubish] Select: ', prompt
  end

  def test_ps3_with_time
    ENV['PS3'] = '(\A) #? '
    prompt = @repl.send(:select_prompt)
    assert_match(/^\(\d{2}:\d{2}\) #\? $/, prompt)
  end

  def test_ps3_with_user
    ENV['PS3'] = '\u> '
    prompt = @repl.send(:select_prompt)
    expected_user = ENV['USER'] || Etc.getlogin || 'user'
    assert_equal "#{expected_user}> ", prompt
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

  # PROMPT_COMMAND tests
  def test_prompt_command_not_set
    ENV.delete('PROMPT_COMMAND')
    Rubish::Builtins.set_array('PROMPT_COMMAND', [])
    # Should not raise any errors
    @repl.send(:run_prompt_command)
  end

  def test_prompt_command_string
    ENV['PROMPT_COMMAND'] = 'true'
    Rubish::Builtins.set_array('PROMPT_COMMAND', [])
    # Should execute without error
    @repl.send(:run_prompt_command)
  end

  def test_prompt_command_sets_variable
    Dir.chdir(@tempdir) do
      ENV['PROMPT_COMMAND'] = 'echo "executed" > prompt_test.txt'
      Rubish::Builtins.set_array('PROMPT_COMMAND', [])
      @repl.send(:run_prompt_command)
      assert File.exist?('prompt_test.txt'), 'PROMPT_COMMAND should have been executed'
      assert_equal "executed\n", File.read('prompt_test.txt')
    end
  end

  def test_prompt_command_preserves_exit_status
    @repl.instance_variable_set(:@last_status, 42)
    ENV['PROMPT_COMMAND'] = 'true'
    Rubish::Builtins.set_array('PROMPT_COMMAND', [])
    @repl.send(:run_prompt_command)
    # PROMPT_COMMAND should not affect $?
    assert_equal 42, @repl.instance_variable_get(:@last_status)
  end

  def test_prompt_command_array
    Dir.chdir(@tempdir) do
      ENV.delete('PROMPT_COMMAND')
      Rubish::Builtins.set_array('PROMPT_COMMAND', [
        'echo "first" > first.txt',
        'echo "second" > second.txt'
      ])
      @repl.send(:run_prompt_command)
      assert File.exist?('first.txt'), 'First command should have been executed'
      assert File.exist?('second.txt'), 'Second command should have been executed'
      assert_equal "first\n", File.read('first.txt')
      assert_equal "second\n", File.read('second.txt')
    end
  end

  def test_prompt_command_array_takes_precedence
    Dir.chdir(@tempdir) do
      ENV['PROMPT_COMMAND'] = 'echo "string" > string.txt'
      Rubish::Builtins.set_array('PROMPT_COMMAND', ['echo "array" > array.txt'])
      @repl.send(:run_prompt_command)
      # Array should take precedence over string
      assert File.exist?('array.txt'), 'Array command should have been executed'
      assert !File.exist?('string.txt'), 'String command should not have been executed'
    end
  end

  def test_prompt_command_with_multiple_commands
    Dir.chdir(@tempdir) do
      ENV['PROMPT_COMMAND'] = 'echo "one" > one.txt; echo "two" > two.txt'
      Rubish::Builtins.set_array('PROMPT_COMMAND', [])
      @repl.send(:run_prompt_command)
      assert File.exist?('one.txt')
      assert File.exist?('two.txt')
    end
  end

  def test_prompt_command_empty_string
    ENV['PROMPT_COMMAND'] = ''
    Rubish::Builtins.set_array('PROMPT_COMMAND', [])
    # Should not raise any errors
    @repl.send(:run_prompt_command)
  end

  def test_prompt_command_skips_nil_in_array
    Dir.chdir(@tempdir) do
      ENV.delete('PROMPT_COMMAND')
      arr = []
      arr[0] = 'echo "zero" > zero.txt'
      arr[2] = 'echo "two" > two.txt'  # arr[1] is nil
      Rubish::Builtins.set_array('PROMPT_COMMAND', arr)
      @repl.send(:run_prompt_command)
      assert File.exist?('zero.txt')
      assert File.exist?('two.txt')
    end
  end

  # PROMPT_DIRTRIM tests

  def test_prompt_dirtrim_not_set
    ENV.delete('PROMPT_DIRTRIM')
    path = '/very/deep/nested/directory/structure'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal path, result
  end

  def test_prompt_dirtrim_zero
    ENV['PROMPT_DIRTRIM'] = '0'
    path = '/very/deep/nested/directory'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal path, result
  end

  def test_prompt_dirtrim_negative
    ENV['PROMPT_DIRTRIM'] = '-1'
    path = '/very/deep/nested/directory'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal path, result
  end

  def test_prompt_dirtrim_absolute_path
    ENV['PROMPT_DIRTRIM'] = '2'
    path = '/home/user/projects/myapp/src/components'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal '.../src/components', result
  end

  def test_prompt_dirtrim_absolute_path_three
    ENV['PROMPT_DIRTRIM'] = '3'
    path = '/home/user/projects/myapp/src/components'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal '.../myapp/src/components', result
  end

  def test_prompt_dirtrim_home_path
    ENV['PROMPT_DIRTRIM'] = '2'
    path = '~/projects/myapp/src/components'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal '~/.../src/components', result
  end

  def test_prompt_dirtrim_home_path_three
    ENV['PROMPT_DIRTRIM'] = '3'
    path = '~/projects/myapp/src/components'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal '~/.../myapp/src/components', result
  end

  def test_prompt_dirtrim_home_only
    ENV['PROMPT_DIRTRIM'] = '2'
    path = '~'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal '~', result
  end

  def test_prompt_dirtrim_path_shorter_than_trim
    ENV['PROMPT_DIRTRIM'] = '5'
    path = '/home/user/projects'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal path, result
  end

  def test_prompt_dirtrim_path_equal_to_trim
    ENV['PROMPT_DIRTRIM'] = '3'
    path = '/home/user/projects'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal path, result
  end

  def test_prompt_dirtrim_home_shorter_than_trim
    ENV['PROMPT_DIRTRIM'] = '5'
    path = '~/projects/app'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal path, result
  end

  def test_prompt_dirtrim_one
    ENV['PROMPT_DIRTRIM'] = '1'
    path = '/home/user/projects/myapp'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal '.../myapp', result
  end

  def test_prompt_dirtrim_with_ps1
    ENV['PS1'] = '\w$ '
    ENV['PROMPT_DIRTRIM'] = '2'

    # Create a deep directory structure
    deep_dir = File.join(@tempdir, 'a', 'b', 'c', 'd')
    FileUtils.mkdir_p(deep_dir)
    Dir.chdir(deep_dir)

    prompt = @repl.send(:prompt)
    assert_match(/\.\.\.\/c\/d\$ $/, prompt)
  end

  def test_prompt_dirtrim_with_home_in_ps1
    ENV['PS1'] = '\w$ '
    ENV['PROMPT_DIRTRIM'] = '2'

    # Create deep directory under home
    home = ENV['HOME']
    if home && File.directory?(home)
      deep_dir = File.join(home, 'test_prompt_dirtrim_deep', 'level1', 'level2', 'level3')
      FileUtils.mkdir_p(deep_dir)
      begin
        Dir.chdir(deep_dir)
        prompt = @repl.send(:prompt)
        assert_match(/~\/\.\.\.\/level2\/level3\$ $/, prompt)
      ensure
        FileUtils.rm_rf(File.join(home, 'test_prompt_dirtrim_deep'))
      end
    end
  end

  def test_prompt_dirtrim_empty_string
    ENV['PROMPT_DIRTRIM'] = ''
    path = '/very/deep/nested/directory'
    result = @repl.send(:trim_prompt_dir, path)
    assert_equal path, result
  end

  def test_prompt_dirtrim_non_numeric
    ENV['PROMPT_DIRTRIM'] = 'abc'
    path = '/very/deep/nested/directory'
    result = @repl.send(:trim_prompt_dir, path)
    # to_i returns 0 for non-numeric, so no trimming
    assert_equal path, result
  end

  # RPROMPT tests (right prompt like zsh)

  def test_rprompt_nil_when_not_set
    ENV.delete('RPROMPT')
    ENV.delete('RPS1')
    result = @repl.send(:right_prompt)
    assert_nil result
  end

  def test_rprompt_from_env
    ENV['RPROMPT'] = 'right>'
    result = @repl.send(:right_prompt)
    assert_equal 'right>', result
  end

  def test_rprompt_from_rps1
    ENV.delete('RPROMPT')
    ENV['RPS1'] = 'rps1>'
    result = @repl.send(:right_prompt)
    assert_equal 'rps1>', result
  end

  def test_rprompt_prefers_rprompt_over_rps1
    ENV['RPROMPT'] = 'rprompt>'
    ENV['RPS1'] = 'rps1>'
    result = @repl.send(:right_prompt)
    assert_equal 'rprompt>', result
  end

  def test_rprompt_expands_escape_sequences
    ENV['RPROMPT'] = '\u@\h'
    result = @repl.send(:right_prompt)
    expected_user = ENV['USER'] || Etc.getlogin || 'user'
    expected_host = Socket.gethostname.split('.').first
    assert_equal "#{expected_user}@#{expected_host}", result
  end

  def test_visible_length_plain_text
    result = @repl.send(:visible_length, 'hello')
    assert_equal 5, result
  end

  def test_visible_length_with_ansi_codes
    # Text with color codes should only count visible characters
    result = @repl.send(:visible_length, "\e[31mhello\e[0m")
    assert_equal 5, result
  end

  def test_visible_length_complex_ansi
    result = @repl.send(:visible_length, "\e[1;32mbold green\e[0m text")
    assert_equal 15, result  # "bold green text"
  end

  def test_terminal_width_returns_positive
    result = @repl.send(:terminal_width)
    assert result > 0
  end

  # Zsh-style prompt escapes

  def test_zsh_username
    ENV['RPROMPT'] = '%n'
    result = @repl.send(:right_prompt)
    expected_user = ENV['USER'] || Etc.getlogin || 'user'
    assert_equal expected_user, result
  end

  def test_zsh_hostname_short
    ENV['RPROMPT'] = '%m'
    result = @repl.send(:right_prompt)
    expected_host = Socket.gethostname.split('.').first
    assert_equal expected_host, result
  end

  def test_zsh_hostname_full
    ENV['RPROMPT'] = '%M'
    result = @repl.send(:right_prompt)
    assert_equal Socket.gethostname, result
  end

  def test_zsh_working_directory
    ENV['RPROMPT'] = '%~'
    Dir.chdir(ENV['HOME'])
    result = @repl.send(:right_prompt)
    assert_equal '~', result
  end

  def test_zsh_time_24h
    ENV['RPROMPT'] = '%T'
    result = @repl.send(:right_prompt)
    assert_match(/\d{2}:\d{2}/, result)
  end

  def test_zsh_time_with_seconds
    ENV['RPROMPT'] = '%*'
    result = @repl.send(:right_prompt)
    assert_match(/\d{2}:\d{2}:\d{2}/, result)
  end

  def test_zsh_date
    ENV['RPROMPT'] = '%D'
    result = @repl.send(:right_prompt)
    assert_match(/\d{2}-\d{2}-\d{2}/, result)
  end

  def test_zsh_custom_date_format
    ENV['RPROMPT'] = '%D{%Y-%m-%d}'
    result = @repl.send(:right_prompt)
    assert_match(/\d{4}-\d{2}-\d{2}/, result)
  end

  def test_zsh_exit_status
    ENV['RPROMPT'] = '%?'
    @repl.instance_variable_set(:@last_status, 42)
    result = @repl.send(:right_prompt)
    assert_equal '42', result
  end

  def test_zsh_literal_percent
    ENV['RPROMPT'] = '100%%'
    result = @repl.send(:right_prompt)
    assert_equal '100%', result
  end

  def test_zsh_privilege_indicator
    ENV['PROMPT'] = '%# '
    result = @repl.send(:prompt)
    # Non-root users get %, root gets #
    expected = Process.uid == 0 ? '# ' : '% '
    assert_equal expected, result
  end

  def test_zsh_foreground_color
    ENV['RPROMPT'] = '%F{red}red%f'
    result = @repl.send(:right_prompt)
    assert_match(/\e\[31m/, result)  # Red foreground
    assert_match(/\e\[39m/, result)  # Reset foreground
  end

  def test_zsh_foreground_color_number
    ENV['RPROMPT'] = '%F{4}blue%f'
    result = @repl.send(:right_prompt)
    assert_match(/\e\[34m/, result)  # Blue foreground (30 + 4)
  end

  def test_zsh_bold
    ENV['RPROMPT'] = '%Bbold%b'
    result = @repl.send(:right_prompt)
    assert_match(/\e\[1m/, result)   # Bold on
    assert_match(/\e\[22m/, result)  # Bold off
  end

  def test_zsh_256_color
    ENV['RPROMPT'] = '%F{208}orange%f'
    result = @repl.send(:right_prompt)
    assert_match(/\e\[38;5;208m/, result)  # 256-color foreground
  end

  def test_mixed_bash_and_zsh_escapes
    ENV['RPROMPT'] = '\u@%m'  # Bash \u and zsh %m
    result = @repl.send(:right_prompt)
    expected_user = ENV['USER'] || Etc.getlogin || 'user'
    expected_host = Socket.gethostname.split('.').first
    assert_equal "#{expected_user}@#{expected_host}", result
  end

  # Test prompt_subst (zsh option) - enables parameter expansion in prompts
  def test_prompt_subst_variable_expansion
    Rubish::Builtins.set_zsh_option('prompt_subst', true)
    ENV['TEST_PROMPT_VAR'] = 'hello'
    ENV['PS1'] = '$TEST_PROMPT_VAR $ '
    result = @repl.send(:prompt)
    assert_equal 'hello $ ', result
  ensure
    Rubish::Builtins.set_zsh_option('prompt_subst', false)
    ENV.delete('TEST_PROMPT_VAR')
  end

  def test_prompt_subst_command_substitution
    Rubish::Builtins.set_zsh_option('prompt_subst', true)
    ENV['PS1'] = '$(echo world) $ '
    result = @repl.send(:prompt)
    assert_equal 'world $ ', result
  ensure
    Rubish::Builtins.set_zsh_option('prompt_subst', false)
  end

  def test_prompt_subst_disabled_no_expansion
    Rubish::Builtins.set_zsh_option('prompt_subst', false)
    Rubish::Builtins.shell_options['promptvars'] = false
    ENV['TEST_PROMPT_VAR'] = 'hello'
    ENV['PS1'] = '$TEST_PROMPT_VAR $ '
    result = @repl.send(:prompt)
    assert_equal '$TEST_PROMPT_VAR $ ', result
  ensure
    Rubish::Builtins.shell_options['promptvars'] = true
    ENV.delete('TEST_PROMPT_VAR')
  end

  def test_prompt_subst_with_zsh_escapes
    Rubish::Builtins.set_zsh_option('prompt_subst', true)
    ENV['MY_DIR'] = '/tmp'
    ENV['PS1'] = '%n:$MY_DIR $ '
    result = @repl.send(:prompt)
    expected_user = ENV['USER'] || Etc.getlogin || 'user'
    assert_equal "#{expected_user}:/tmp $ ", result
  ensure
    Rubish::Builtins.set_zsh_option('prompt_subst', false)
    ENV.delete('MY_DIR')
  end
end
