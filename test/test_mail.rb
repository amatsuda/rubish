# frozen_string_literal: true

require_relative 'test_helper'

class TestMAIL < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_mail_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def check_mail
    @repl.send(:check_mail)
  end

  def parse_mail_paths
    @repl.send(:parse_mail_paths)
  end

  def reset_mail_check_time(offset = -100)
    # Reset last mail check time to allow immediate checking
    @repl.instance_variable_set(:@last_mail_check, Time.now + offset)
  end

  def reset_mail_mtimes
    @repl.instance_variable_set(:@mail_mtimes, {})
  end

  # parse_mail_paths tests

  def test_parse_mail_paths_returns_empty_when_nothing_set
    ENV.delete('MAIL')
    ENV.delete('MAILPATH')

    result = parse_mail_paths

    assert_equal [], result
  end

  def test_parse_mail_paths_uses_mail_when_mailpath_not_set
    ENV.delete('MAILPATH')
    ENV['MAIL'] = '/var/mail/user'

    result = parse_mail_paths

    assert_equal [['/var/mail/user', nil]], result
  end

  def test_parse_mail_paths_uses_mailpath_over_mail
    ENV['MAIL'] = '/var/mail/user'
    ENV['MAILPATH'] = '/other/mail'

    result = parse_mail_paths

    assert_equal [['/other/mail', nil]], result
  end

  def test_parse_mail_paths_handles_multiple_paths
    ENV['MAILPATH'] = '/mail1:/mail2:/mail3'

    result = parse_mail_paths

    assert_equal [['/mail1', nil], ['/mail2', nil], ['/mail3', nil]], result
  end

  def test_parse_mail_paths_extracts_custom_messages
    ENV['MAILPATH'] = '/mail1?New mail arrived:/mail2?Check your inbox'

    result = parse_mail_paths

    assert_equal [['/mail1', 'New mail arrived'], ['/mail2', 'Check your inbox']], result
  end

  def test_parse_mail_paths_handles_mixed_with_and_without_messages
    ENV['MAILPATH'] = '/mail1?Custom message:/mail2:/mail3?Another message'

    result = parse_mail_paths

    assert_equal [['/mail1', 'Custom message'], ['/mail2', nil], ['/mail3', 'Another message']], result
  end

  def test_parse_mail_paths_empty_mail_returns_empty
    ENV.delete('MAILPATH')
    ENV['MAIL'] = ''

    result = parse_mail_paths

    assert_equal [], result
  end

  def test_parse_mail_paths_empty_mailpath_returns_empty
    ENV['MAILPATH'] = ''
    ENV['MAIL'] = '/var/mail/user'

    result = parse_mail_paths

    # Empty MAILPATH is falsy, falls back to MAIL
    assert_equal [['/var/mail/user', nil]], result
  end

  # MAILCHECK interval tests

  def test_mailcheck_default_60_seconds
    mailfile = File.join(@tempdir, 'mailbox')
    File.write(mailfile, 'mail content')
    ENV['MAIL'] = mailfile
    ENV.delete('MAILCHECK')

    # First check - should record mtime
    reset_mail_check_time(-100)
    check_mail

    # Immediately check again - should be blocked by 60 second interval
    output = capture_stdout do
      sleep 0.1
      File.write(mailfile, 'new mail')
      check_mail
    end

    assert_equal '', output
  end

  def test_mailcheck_zero_checks_every_time
    mailfile = File.join(@tempdir, 'mailbox')
    File.write(mailfile, 'mail content')
    ENV['MAIL'] = mailfile
    ENV['MAILCHECK'] = '0'

    # First check - records mtime
    reset_mail_check_time
    check_mail

    # Immediately modify and check - should detect with MAILCHECK=0
    output = capture_stdout do
      sleep 0.1
      File.write(mailfile, 'new mail')
      check_mail
    end

    assert_match(/You have new mail/, output)
  end

  def test_mailcheck_negative_disables_checking
    mailfile = File.join(@tempdir, 'mailbox')
    File.write(mailfile, 'mail content')
    ENV['MAIL'] = mailfile
    ENV['MAILCHECK'] = '-1'

    output = capture_stdout do
      reset_mail_check_time(-100)
      check_mail
      sleep 0.1
      File.write(mailfile, 'new mail')
      reset_mail_check_time(-100)
      check_mail
    end

    assert_equal '', output
  end

  def test_mailcheck_custom_interval
    mailfile = File.join(@tempdir, 'mailbox')
    File.write(mailfile, 'mail content')
    ENV['MAIL'] = mailfile
    ENV['MAILCHECK'] = '1'

    # First check
    reset_mail_check_time(-100)
    check_mail

    # Should be blocked by 1 second interval
    output1 = capture_stdout do
      File.write(mailfile, 'new mail 1')
      check_mail
    end

    # Wait for interval and check again
    sleep 1.1
    output2 = capture_stdout do
      File.write(mailfile, 'new mail 2')
      reset_mail_mtimes
      check_mail
      sleep 0.1
      File.write(mailfile, 'new mail 3')
      @repl.instance_variable_set(:@last_mail_check, Time.now - 2)
      check_mail
    end

    assert_equal '', output1
    assert_match(/You have new mail/, output2)
  end

  # Mail notification tests

  def test_no_notification_on_first_check
    mailfile = File.join(@tempdir, 'mailbox')
    File.write(mailfile, 'existing mail')
    ENV['MAIL'] = mailfile
    ENV['MAILCHECK'] = '0'

    output = capture_stdout do
      reset_mail_check_time
      reset_mail_mtimes
      check_mail
    end

    assert_equal '', output
  end

  def test_notification_when_mail_modified
    mailfile = File.join(@tempdir, 'mailbox')
    File.write(mailfile, 'existing mail')
    ENV['MAIL'] = mailfile
    ENV['MAILCHECK'] = '0'

    # First check to record mtime
    reset_mail_check_time
    reset_mail_mtimes
    check_mail

    # Modify mail file
    sleep 0.1
    File.write(mailfile, 'new mail arrived')

    output = capture_stdout do
      check_mail
    end

    assert_match(/You have new mail in #{Regexp.escape(mailfile)}/, output)
  end

  def test_notification_uses_custom_message_from_mailpath
    mailfile = File.join(@tempdir, 'mailbox')
    File.write(mailfile, 'existing mail')
    # Note: message cannot contain ':' as it's used as path separator
    ENV['MAILPATH'] = "#{mailfile}?Check your email!"
    ENV['MAILCHECK'] = '0'

    # First check
    reset_mail_check_time
    reset_mail_mtimes
    check_mail

    # Modify mail
    sleep 0.1
    File.write(mailfile, 'new mail')

    output = capture_stdout do
      check_mail
    end

    assert_match(/Check your email!/, output)
    assert_not_match(/You have new mail/, output)
  end

  def test_no_notification_for_nonexistent_file
    ENV['MAIL'] = '/nonexistent/mail/file'
    ENV['MAILCHECK'] = '0'

    output = capture_stdout do
      reset_mail_check_time
      check_mail
    end

    assert_equal '', output
  end

  def test_no_notification_for_empty_file
    mailfile = File.join(@tempdir, 'mailbox')
    File.write(mailfile, '')
    ENV['MAIL'] = mailfile
    ENV['MAILCHECK'] = '0'

    output = capture_stdout do
      reset_mail_check_time
      check_mail
    end

    assert_equal '', output
  end

  def test_no_notification_for_directory
    maildir = File.join(@tempdir, 'maildir')
    FileUtils.mkdir(maildir)
    ENV['MAIL'] = maildir
    ENV['MAILCHECK'] = '0'

    output = capture_stdout do
      reset_mail_check_time
      check_mail
    end

    assert_equal '', output
  end

  def test_multiple_mail_files_notification
    mail1 = File.join(@tempdir, 'mail1')
    mail2 = File.join(@tempdir, 'mail2')
    File.write(mail1, 'content1')
    File.write(mail2, 'content2')
    ENV['MAILPATH'] = "#{mail1}:#{mail2}"
    ENV['MAILCHECK'] = '0'

    # First check
    reset_mail_check_time
    reset_mail_mtimes
    check_mail

    # Modify both files
    sleep 0.1
    File.write(mail1, 'new1')
    File.write(mail2, 'new2')

    output = capture_stdout do
      check_mail
    end

    assert_match(/You have new mail in #{Regexp.escape(mail1)}/, output)
    assert_match(/You have new mail in #{Regexp.escape(mail2)}/, output)
  end

  def test_only_modified_files_trigger_notification
    mail1 = File.join(@tempdir, 'mail1')
    mail2 = File.join(@tempdir, 'mail2')
    File.write(mail1, 'content1')
    File.write(mail2, 'content2')
    ENV['MAILPATH'] = "#{mail1}:#{mail2}"
    ENV['MAILCHECK'] = '0'

    # First check
    reset_mail_check_time
    reset_mail_mtimes
    check_mail

    # Only modify mail1
    sleep 0.1
    File.write(mail1, 'new1')

    output = capture_stdout do
      check_mail
    end

    assert_match(/You have new mail in #{Regexp.escape(mail1)}/, output)
    assert_not_match(/#{Regexp.escape(mail2)}/, output)
  end

  def test_no_repeated_notification_for_same_modification
    mailfile = File.join(@tempdir, 'mailbox')
    File.write(mailfile, 'content')
    ENV['MAIL'] = mailfile
    ENV['MAILCHECK'] = '0'

    # First check
    reset_mail_check_time
    reset_mail_mtimes
    check_mail

    # Modify mail
    sleep 0.1
    File.write(mailfile, 'new mail')

    # First notification
    output1 = capture_stdout { check_mail }

    # Check again without modification - should not notify again
    output2 = capture_stdout { check_mail }

    assert_match(/You have new mail/, output1)
    assert_equal '', output2
  end
end
