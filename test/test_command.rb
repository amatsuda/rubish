# frozen_string_literal: true

require_relative 'test_helper'

class TestCommand < Test::Unit::TestCase
  def test_simple_command
    output = capture_command_output do |f|
      cmd = Rubish::Command.new('echo', 'hello')
      cmd.redirect_out(f.path)
      cmd.run
    end
    assert_equal "hello\n", output
  end

  def test_command_with_multiple_args
    output = capture_command_output do |f|
      cmd = Rubish::Command.new('echo', 'hello', 'world')
      cmd.redirect_out(f.path)
      cmd.run
    end
    assert_equal "hello world\n", output
  end

  def test_command_status
    cmd = Rubish::Command.new('true')
    cmd.run
    assert cmd.ran?
    assert cmd.status.success?
  end

  def test_pipe
    output = capture_command_output do |f|
      left = Rubish::Command.new('echo', 'hello world')
      right = Rubish::Command.new('wc', '-w')
      right.redirect_out(f.path)
      left | right
    end
    assert_match(/2/, output.strip)
  end

  # TODO: three-command pipes need architectural fix
  # The issue is (cmd1 | cmd2) runs cmd2, then trying to pipe
  # the result to cmd3 fails because cmd2 already ran
  def test_pipe_with_grep
    output = capture_command_output do |f|
      cmd1 = Rubish::Command.new('printf', "apple\nbanana\ncherry")
      cmd2 = Rubish::Command.new('grep', 'banana')
      cmd2.redirect_out(f.path)
      cmd1 | cmd2
    end
    assert_equal "banana\n", output
  end

  def test_redirect_out
    Tempfile.create('rubish_test') do |f|
      cmd = Rubish::Command.new('echo', 'hello')
      cmd.redirect_out(f.path)
      cmd.run

      assert_equal "hello\n", File.read(f.path)
    end
  end

  def test_redirect_append
    Tempfile.create('rubish_test') do |f|
      File.write(f.path, "first\n")

      cmd = Rubish::Command.new('echo', 'second')
      cmd.redirect_append(f.path)
      cmd.run

      assert_equal "first\nsecond\n", File.read(f.path)
    end
  end

  def test_redirect_in
    Tempfile.create('rubish_test') do |f|
      File.write(f.path, "hello from file\n")

      output = capture_command_output do |out|
        cmd = Rubish::Command.new('cat')
        cmd.redirect_in(f.path)
        cmd.redirect_out(out.path)
        cmd.run
      end

      assert_equal "hello from file\n", output
    end
  end

  def test_run_only_once
    Tempfile.create('rubish_test') do |f|
      cmd = Rubish::Command.new('echo', 'hello')
      cmd.redirect_out(f.path)
      cmd.run
      assert cmd.ran?

      # Clear file and run again
      File.write(f.path, '')
      cmd.run

      # Should still be empty (no second run)
      assert_equal '', File.read(f.path)
    end
  end

  private

  def capture_command_output
    Tempfile.create('rubish_test') do |f|
      yield f
      return File.read(f.path)
    end
  end
end
