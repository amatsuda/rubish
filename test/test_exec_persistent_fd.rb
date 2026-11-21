# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# `exec N>file` keeps descriptor N open in the shell for later commands,
# `>&N` and `<&N` use it, external commands inherit it, `exec N>&-` closes it
class TestExecPersistentFd < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @dir = Dir.mktmpdir('rubish_fd')
    @file = File.join(@dir, 'out.txt')
  end

  def teardown
    execute('exec 3>&- 4>&- 5<&-')
    FileUtils.rm_rf(@dir)
  end

  def test_exec_opens_a_descriptor_that_later_commands_write_to
    execute("exec 3>#{@file}")
    execute('echo one >&3')
    execute('echo two >&3')
    execute('exec 3>&-')
    assert_equal "one\ntwo\n", File.read(@file)
  end

  def test_appending_descriptor
    File.write(@file, "old\n")
    execute("exec 3>>#{@file}")
    execute('echo new >&3')
    execute('exec 3>&-')
    assert_equal "old\nnew\n", File.read(@file)
  end

  def test_external_command_inherits_the_descriptor
    execute("exec 3>#{@file}")
    execute("sh -c 'echo inherited >&3'")
    execute('exec 3>&-')
    assert_equal "inherited\n", File.read(@file)
  end

  def test_descriptor_can_be_duplicated_to_another_descriptor
    execute("exec 3>#{@file}")
    execute('exec 4>&3')
    execute('echo four >&4')
    execute('exec 4>&- 3>&-')
    assert_equal "four\n", File.read(@file)
  end

  def test_stderr_can_be_sent_to_the_descriptor
    execute("exec 3>#{@file}")
    execute("cat #{File.join(@dir, 'missing')} 2>&3")
    execute('exec 3>&-')
    assert_match(/missing: No such file or directory/, File.read(@file))
  end

  def test_input_descriptor_feeds_read_u_and_stdin_duplication
    File.write(@file, "first\nsecond\n")
    out = File.join(@dir, 'got.txt')
    execute("exec 5<#{@file}")
    execute('read -u 5 line')
    execute("cat <&5 > #{out}")
    execute('exec 5<&-')
    assert_equal 'first', get_shell_var('line')
    assert_equal "second\n", File.read(out)
  end

  def test_closed_descriptor_is_a_bad_file_descriptor_again
    execute("exec 3>#{@file}")
    execute('exec 3>&-')
    err = capture_stderr { execute('echo gone >&3') }
    assert_match(/3: Bad file descriptor/, err)
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_exec_dup_of_unknown_descriptor_fails
    err = capture_stderr { execute('exec 4>&9') }
    assert_match(/9: Bad file descriptor/, err)
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end
end
