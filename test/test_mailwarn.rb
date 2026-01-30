# frozen_string_literal: true

require_relative 'test_helper'

class TestMailwarn < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_mailwarn_test')
    @mail_file = File.join(@tempdir, 'mailbox')
  end

  def teardown
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def check_mail
    @repl.send(:check_mail)
  end

  # mailwarn is disabled by default
  def test_mailwarn_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('mailwarn')
  end

  def test_mailwarn_can_be_enabled
    execute('shopt -s mailwarn')
    assert Rubish::Builtins.shopt_enabled?('mailwarn')
  end

  def test_mailwarn_can_be_disabled
    execute('shopt -s mailwarn')
    execute('shopt -u mailwarn')
    assert_false Rubish::Builtins.shopt_enabled?('mailwarn')
  end

  # Without mailwarn: no warning when mail is read
  def test_no_read_warning_without_mailwarn
    # Create mail file with content
    File.write(@mail_file, "You have mail\n")
    ENV['MAIL'] = @mail_file
    ENV['MAILCHECK'] = '0'

    # First check - records initial state
    output = capture_output { check_mail }
    assert_equal '', output

    # Simulate mail being read by setting atime > mtime
    mtime = File.mtime(@mail_file)
    File.utime(mtime + 10, mtime, @mail_file)  # atime = mtime + 10

    # Without mailwarn, no warning about mail being read
    output = capture_output { check_mail }
    assert_equal '', output
  end

  # With mailwarn: warning when mail is read
  def test_read_warning_with_mailwarn
    execute('shopt -s mailwarn')

    # Create mail file with content
    File.write(@mail_file, "You have mail\n")
    ENV['MAIL'] = @mail_file
    ENV['MAILCHECK'] = '0'

    # First check - records initial state
    output = capture_output { check_mail }
    assert_equal '', output

    # Simulate mail being read by setting atime > mtime
    mtime = File.mtime(@mail_file)
    File.utime(mtime + 10, mtime, @mail_file)  # atime = mtime + 10

    # With mailwarn, should warn about mail being read
    output = capture_output { check_mail }
    assert_match(/has been read/, output)
    assert_match(/#{Regexp.escape(@mail_file)}/, output)
  end

  # New mail notification still works with mailwarn
  def test_new_mail_notification_with_mailwarn
    execute('shopt -s mailwarn')

    # Create mail file with content
    File.write(@mail_file, "Initial mail\n")
    ENV['MAIL'] = @mail_file
    ENV['MAILCHECK'] = '0'

    # First check - records initial state
    output = capture_output { check_mail }
    assert_equal '', output

    # Add new mail (updates mtime)
    sleep 0.1  # Ensure mtime changes
    File.write(@mail_file, "Initial mail\nNew mail\n")

    # Should notify about new mail
    output = capture_output { check_mail }
    assert_match(/You have new mail/, output)
  end

  # mailwarn only warns once per read
  def test_mailwarn_warns_once_per_read
    execute('shopt -s mailwarn')

    File.write(@mail_file, "Mail content\n")
    ENV['MAIL'] = @mail_file
    ENV['MAILCHECK'] = '0'

    # First check - records initial state
    capture_output { check_mail }

    # Simulate mail being read
    mtime = File.mtime(@mail_file)
    File.utime(mtime + 10, mtime, @mail_file)

    # First warning
    output1 = capture_output { check_mail }
    assert_match(/has been read/, output1)

    # Second check - should not warn again (atime hasn't changed)
    output2 = capture_output { check_mail }
    assert_equal '', output2
  end

  # mailwarn with multiple reads
  def test_mailwarn_multiple_reads
    execute('shopt -s mailwarn')

    File.write(@mail_file, "Mail content\n")
    ENV['MAIL'] = @mail_file
    ENV['MAILCHECK'] = '0'

    # First check - records initial state
    capture_output { check_mail }

    # First read
    mtime = File.mtime(@mail_file)
    File.utime(mtime + 10, mtime, @mail_file)

    output1 = capture_output { check_mail }
    assert_match(/has been read/, output1)

    # Second read (atime increases again)
    File.utime(mtime + 20, mtime, @mail_file)

    output2 = capture_output { check_mail }
    assert_match(/has been read/, output2)
  end

  # mailwarn doesn't warn if atime <= mtime
  def test_mailwarn_no_warning_if_atime_not_greater_than_mtime
    execute('shopt -s mailwarn')

    File.write(@mail_file, "Mail content\n")
    ENV['MAIL'] = @mail_file
    ENV['MAILCHECK'] = '0'

    # First check - records initial state
    capture_output { check_mail }

    # Set atime = mtime (not read since last write), keeping original mtime
    mtime = File.mtime(@mail_file)
    File.utime(mtime, mtime, @mail_file)  # atime = mtime, no change to mtime

    # Should not warn (atime not > mtime, and mtime didn't change)
    output = capture_output { check_mail }
    assert_equal '', output
  end

  # Empty mail file is ignored
  def test_mailwarn_ignores_empty_file
    execute('shopt -s mailwarn')

    File.write(@mail_file, '')  # Empty file
    ENV['MAIL'] = @mail_file
    ENV['MAILCHECK'] = '0'

    # Simulate read
    mtime = File.mtime(@mail_file)
    File.utime(mtime + 10, mtime, @mail_file)

    output = capture_output { check_mail }
    assert_equal '', output
  end

  # MAILPATH with mailwarn
  def test_mailwarn_with_mailpath
    execute('shopt -s mailwarn')

    mail_file2 = File.join(@tempdir, 'mailbox2')
    File.write(@mail_file, "Mail 1\n")
    File.write(mail_file2, "Mail 2\n")

    ENV['MAILPATH'] = "#{@mail_file}:#{mail_file2}"
    ENV['MAILCHECK'] = '0'

    # First check - records initial state
    capture_output { check_mail }

    # Read only first mailbox
    mtime = File.mtime(@mail_file)
    File.utime(mtime + 10, mtime, @mail_file)

    output = capture_output { check_mail }
    assert_match(/#{Regexp.escape(@mail_file)}/, output)
    assert_match(/has been read/, output)
    # Should not mention second mailbox
    refute_match(/#{Regexp.escape(mail_file2)}/, output)
  end

  # Disabling mailwarn stops warnings
  def test_disable_mailwarn_stops_warnings
    execute('shopt -s mailwarn')

    File.write(@mail_file, "Mail content\n")
    ENV['MAIL'] = @mail_file
    ENV['MAILCHECK'] = '0'

    # First check - records initial state
    capture_output { check_mail }

    # Simulate read
    mtime = File.mtime(@mail_file)
    File.utime(mtime + 10, mtime, @mail_file)

    # Disable mailwarn before check
    execute('shopt -u mailwarn')

    output = capture_output { check_mail }
    assert_equal '', output
  end

  # Non-existent mail file doesn't cause error
  def test_mailwarn_nonexistent_file
    execute('shopt -s mailwarn')

    ENV['MAIL'] = '/nonexistent/mailbox'
    ENV['MAILCHECK'] = '0'

    output = capture_output { check_mail }
    assert_equal '', output
  end
end
