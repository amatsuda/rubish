# frozen_string_literal: true

require_relative 'test_helper'

class TestHistoryBuiltin < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_history_builtin_test')
    Reline::HISTORY.clear
    Rubish::Builtins.last_history_line = 0
    Rubish::Builtins.clear_history_timestamps
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Reline::HISTORY.clear
    Rubish::Builtins.clear_history_timestamps
    FileUtils.rm_rf(@tempdir)
  end

  # Basic display tests

  def test_history_shows_all_entries
    Reline::HISTORY << 'ls'
    Reline::HISTORY << 'pwd'
    Reline::HISTORY << 'echo hello'

    output = capture_output { Rubish::Builtins.run_history([]) }

    assert_match(/1  ls/, output)
    assert_match(/2  pwd/, output)
    assert_match(/3  echo hello/, output)
  end

  def test_history_with_count
    Reline::HISTORY << 'cmd1'
    Reline::HISTORY << 'cmd2'
    Reline::HISTORY << 'cmd3'
    Reline::HISTORY << 'cmd4'
    Reline::HISTORY << 'cmd5'

    output = capture_output { Rubish::Builtins.run_history(['3']) }

    assert_no_match(/cmd1/, output)
    assert_no_match(/cmd2/, output)
    assert_match(/3  cmd3/, output)
    assert_match(/4  cmd4/, output)
    assert_match(/5  cmd5/, output)
  end

  def test_history_count_larger_than_history
    Reline::HISTORY << 'only'
    Reline::HISTORY << 'two'

    output = capture_output { Rubish::Builtins.run_history(['10']) }

    assert_match(/1  only/, output)
    assert_match(/2  two/, output)
  end

  # -c: clear history

  def test_history_clear
    Reline::HISTORY << 'ls'
    Reline::HISTORY << 'pwd'

    result = Rubish::Builtins.run_history(['-c'])

    assert result
    assert_equal 0, Reline::HISTORY.size
  end

  # -d offset: delete entry

  def test_history_delete
    Reline::HISTORY << 'first'
    Reline::HISTORY << 'second'
    Reline::HISTORY << 'third'

    result = Rubish::Builtins.run_history(['-d', '2'])

    assert result
    assert_equal 2, Reline::HISTORY.size
    assert_equal ['first', 'third'], Reline::HISTORY.to_a
  end

  def test_history_delete_first
    Reline::HISTORY << 'first'
    Reline::HISTORY << 'second'

    Rubish::Builtins.run_history(['-d', '1'])

    assert_equal ['second'], Reline::HISTORY.to_a
  end

  def test_history_delete_last
    Reline::HISTORY << 'first'
    Reline::HISTORY << 'second'

    Rubish::Builtins.run_history(['-d', '2'])

    assert_equal ['first'], Reline::HISTORY.to_a
  end

  def test_history_delete_out_of_range
    Reline::HISTORY << 'only'

    stderr = capture_stderr { result = Rubish::Builtins.run_history(['-d', '5']) }

    assert_match(/history position out of range/, stderr)
  end

  def test_history_delete_missing_argument
    stderr = capture_stderr { result = Rubish::Builtins.run_history(['-d']) }

    assert_match(/option requires an argument/, stderr)
  end

  # -s: store args as history entry

  def test_history_store
    result = Rubish::Builtins.run_history(['-s', 'echo', 'hello', 'world'])

    assert result
    assert_equal 1, Reline::HISTORY.size
    assert_equal 'echo hello world', Reline::HISTORY[0]
  end

  def test_history_store_single_word
    Rubish::Builtins.run_history(['-s', 'pwd'])

    assert_equal ['pwd'], Reline::HISTORY.to_a
  end

  def test_history_store_empty
    Rubish::Builtins.run_history(['-s'])

    assert_equal 0, Reline::HISTORY.size
  end

  # -p: print expansion

  def test_history_print
    output = capture_output { Rubish::Builtins.run_history(['-p', 'hello', 'world']) }

    assert_equal "hello world\n", output
  end

  # -w: write to file

  def test_history_write
    histfile = File.join(@tempdir, 'history')
    ENV['HISTFILE'] = histfile

    Reline::HISTORY << 'cmd1'
    Reline::HISTORY << 'cmd2'

    result = Rubish::Builtins.run_history(['-w'])

    assert result
    assert File.exist?(histfile)
    assert_equal "cmd1\ncmd2\n", File.read(histfile)
  end

  # -r: read from file (replace)

  def test_history_read
    histfile = File.join(@tempdir, 'history')
    File.write(histfile, "from_file1\nfrom_file2\n")
    ENV['HISTFILE'] = histfile

    Reline::HISTORY << 'existing'

    result = Rubish::Builtins.run_history(['-r'])

    assert result
    assert_equal ['from_file1', 'from_file2'], Reline::HISTORY.to_a
  end

  # -a: append to file

  def test_history_append
    histfile = File.join(@tempdir, 'history')
    File.write(histfile, "old1\nold2\n")
    ENV['HISTFILE'] = histfile

    # Simulate having loaded the old entries
    Reline::HISTORY << 'old1'
    Reline::HISTORY << 'old2'
    Rubish::Builtins.last_history_line = 2

    # Add new entries
    Reline::HISTORY << 'new1'
    Reline::HISTORY << 'new2'

    result = Rubish::Builtins.run_history(['-a'])

    assert result
    content = File.read(histfile)
    assert_equal "old1\nold2\nnew1\nnew2\n", content
  end

  def test_history_append_nothing_new
    histfile = File.join(@tempdir, 'history')
    File.write(histfile, "existing\n")
    ENV['HISTFILE'] = histfile

    Reline::HISTORY << 'existing'
    Rubish::Builtins.last_history_line = 1

    Rubish::Builtins.run_history(['-a'])

    # File should remain unchanged
    assert_equal "existing\n", File.read(histfile)
  end

  # -n: read new lines from file

  def test_history_read_new
    histfile = File.join(@tempdir, 'history')
    File.write(histfile, "line1\nline2\nline3\n")
    ENV['HISTFILE'] = histfile

    # Simulate having already read first 2 lines
    Reline::HISTORY << 'line1'
    Reline::HISTORY << 'line2'
    Rubish::Builtins.last_history_line = 2

    result = Rubish::Builtins.run_history(['-n'])

    assert result
    assert_equal ['line1', 'line2', 'line3'], Reline::HISTORY.to_a
  end

  def test_history_read_new_no_new_lines
    histfile = File.join(@tempdir, 'history')
    File.write(histfile, "line1\nline2\n")
    ENV['HISTFILE'] = histfile

    Reline::HISTORY << 'line1'
    Reline::HISTORY << 'line2'
    Rubish::Builtins.last_history_line = 2

    Rubish::Builtins.run_history(['-n'])

    assert_equal 2, Reline::HISTORY.size
  end

  # Invalid option

  def test_history_invalid_option
    stderr = capture_stderr { result = Rubish::Builtins.run_history(['-x']) }

    assert_match(/invalid option/, stderr)
  end

  # Integration with execute

  def test_history_via_execute
    Reline::HISTORY << 'test1'
    Reline::HISTORY << 'test2'

    output = capture_output { execute('history') }

    assert_match(/1  test1/, output)
    assert_match(/2  test2/, output)
  end

  def test_history_clear_via_execute
    Reline::HISTORY << 'something'

    execute('history -c')

    assert_equal 0, Reline::HISTORY.size
  end

  def test_history_store_via_execute
    execute('history -s stored command')

    assert_equal 1, Reline::HISTORY.size
    assert_equal 'stored command', Reline::HISTORY[0]
  end

  # Line number formatting

  def test_history_line_numbers_formatted
    100.times { |i| Reline::HISTORY << "cmd#{i}" }

    output = capture_output { Rubish::Builtins.run_history(['3']) }

    # Should have proper alignment with 5 character width
    assert_match(/^\s*98  cmd97$/, output)
    assert_match(/^\s*99  cmd98$/, output)
    assert_match(/^\s*100  cmd99$/, output)
  end

  # HISTTIMEFORMAT tests

  def test_histtimeformat_not_set
    Reline::HISTORY << 'cmd1'
    Rubish::Builtins.record_history_timestamp(0)

    ENV.delete('HISTTIMEFORMAT')
    output = capture_output { Rubish::Builtins.run_history([]) }

    # Should show just number and command, no timestamp
    assert_match(/^\s*1  cmd1$/, output)
  end

  def test_histtimeformat_simple_format
    Reline::HISTORY << 'cmd1'
    test_time = Time.new(2024, 6, 15, 10, 30, 45)
    Rubish::Builtins.record_history_timestamp(0, test_time)

    ENV['HISTTIMEFORMAT'] = '%Y-%m-%d %H:%M:%S '
    output = capture_output { Rubish::Builtins.run_history([]) }

    assert_match(/^\s*1  2024-06-15 10:30:45 cmd1$/, output)
  end

  def test_histtimeformat_date_only
    Reline::HISTORY << 'echo hello'
    test_time = Time.new(2024, 12, 25, 14, 0, 0)
    Rubish::Builtins.record_history_timestamp(0, test_time)

    ENV['HISTTIMEFORMAT'] = '%Y/%m/%d '
    output = capture_output { Rubish::Builtins.run_history([]) }

    assert_match(/^\s*1  2024\/12\/25 echo hello$/, output)
  end

  def test_histtimeformat_time_only
    Reline::HISTORY << 'pwd'
    test_time = Time.new(2024, 1, 1, 8, 15, 30)
    Rubish::Builtins.record_history_timestamp(0, test_time)

    ENV['HISTTIMEFORMAT'] = '[%H:%M] '
    output = capture_output { Rubish::Builtins.run_history([]) }

    assert_match(/^\s*1  \[08:15\] pwd$/, output)
  end

  def test_histtimeformat_multiple_entries
    Reline::HISTORY << 'first'
    Reline::HISTORY << 'second'
    Reline::HISTORY << 'third'
    Rubish::Builtins.record_history_timestamp(0, Time.new(2024, 1, 1, 10, 0, 0))
    Rubish::Builtins.record_history_timestamp(1, Time.new(2024, 1, 1, 11, 0, 0))
    Rubish::Builtins.record_history_timestamp(2, Time.new(2024, 1, 1, 12, 0, 0))

    ENV['HISTTIMEFORMAT'] = '%H:%M '
    output = capture_output { Rubish::Builtins.run_history([]) }

    assert_match(/^\s*1  10:00 first$/, output)
    assert_match(/^\s*2  11:00 second$/, output)
    assert_match(/^\s*3  12:00 third$/, output)
  end

  def test_histtimeformat_entry_without_timestamp
    Reline::HISTORY << 'old_command'
    Reline::HISTORY << 'new_command'
    # Only record timestamp for second entry
    Rubish::Builtins.record_history_timestamp(1, Time.new(2024, 6, 1, 9, 0, 0))

    ENV['HISTTIMEFORMAT'] = '%H:%M '
    output = capture_output { Rubish::Builtins.run_history([]) }

    # First entry has no timestamp, shown without time
    assert_match(/^\s*1  old_command$/, output)
    # Second entry has timestamp
    assert_match(/^\s*2  09:00 new_command$/, output)
  end

  def test_histtimeformat_empty_string
    Reline::HISTORY << 'cmd1'
    Rubish::Builtins.record_history_timestamp(0)

    ENV['HISTTIMEFORMAT'] = ''
    output = capture_output { Rubish::Builtins.run_history([]) }

    # Empty format should behave like unset
    assert_match(/^\s*1  cmd1$/, output)
  end

  def test_histtimeformat_with_history_count
    5.times do |i|
      Reline::HISTORY << "cmd#{i}"
      Rubish::Builtins.record_history_timestamp(i, Time.new(2024, 1, 1, i, 0, 0))
    end

    ENV['HISTTIMEFORMAT'] = '%H:00 '
    output = capture_output { Rubish::Builtins.run_history(['2']) }

    # Should only show last 2 entries with timestamps
    assert_no_match(/cmd0/, output)
    assert_no_match(/cmd1/, output)
    assert_no_match(/cmd2/, output)
    assert_match(/^\s*4  03:00 cmd3$/, output)
    assert_match(/^\s*5  04:00 cmd4$/, output)
  end

  def test_history_store_records_timestamp
    ENV['HISTTIMEFORMAT'] = '%Y-%m-%d '

    before = Time.now
    Rubish::Builtins.run_history(['-s', 'stored', 'command'])
    after = Time.now

    output = capture_output { Rubish::Builtins.run_history([]) }

    # Should have today's date
    expected_date = before.strftime('%Y-%m-%d')
    assert_match(/#{expected_date}/, output)
    assert_match(/stored command/, output)
  end

  def test_history_clear_clears_timestamps
    Reline::HISTORY << 'cmd1'
    Rubish::Builtins.record_history_timestamp(0, Time.now)

    Rubish::Builtins.run_history(['-c'])

    # Timestamps should be cleared
    assert_nil Rubish::Builtins.get_history_timestamp(0)
  end

  def test_history_delete_removes_timestamp
    Reline::HISTORY << 'first'
    Reline::HISTORY << 'second'
    Reline::HISTORY << 'third'
    Rubish::Builtins.record_history_timestamp(0, Time.new(2024, 1, 1))
    Rubish::Builtins.record_history_timestamp(1, Time.new(2024, 2, 1))
    Rubish::Builtins.record_history_timestamp(2, Time.new(2024, 3, 1))

    Rubish::Builtins.run_history(['-d', '2'])

    # After deleting index 1, the old index 2 should now be at index 1
    assert_equal Time.new(2024, 1, 1), Rubish::Builtins.get_history_timestamp(0)
    assert_equal Time.new(2024, 3, 1), Rubish::Builtins.get_history_timestamp(1)
    assert_nil Rubish::Builtins.get_history_timestamp(2)
  end

  def test_add_to_history_records_timestamp
    ENV['HISTTIMEFORMAT'] = '%H:%M '

    @repl.send(:add_to_history, 'test command')

    output = capture_output { Rubish::Builtins.run_history([]) }

    # Should have current time (just check format is present)
    assert_match(/^\s*1  \d{2}:\d{2} test command$/, output)
  end

  def test_histtimeformat_via_execute
    Reline::HISTORY << 'existing'
    Rubish::Builtins.record_history_timestamp(0, Time.new(2024, 7, 4, 12, 0, 0))

    ENV['HISTTIMEFORMAT'] = '%m/%d '
    output = capture_output { execute('history') }

    assert_match(/07\/04 existing/, output)
  end
end
