# frozen_string_literal: true

require_relative 'test_helper'

# Every heredoc in the input gets its own body, in order
class TestMultipleHeredocs < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def run_script(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/s.sh", script)
      IO.popen([exe, "#{dir}/s.sh", err: %i[child out]], &:read)
    end
  end

  def test_two_heredocs_on_one_command
    assert_equal "two\n", run_shell("cat <<EOF <<EOF2\none\nEOF\ntwo\nEOF2\n")
  end

  def test_two_heredoc_commands
    assert_equal "a\nb\n", run_shell("cat <<EOF\na\nEOF\ncat <<EOF\nb\nEOF\n")
  end

  def test_heredocs_in_both_branches
    assert_equal "no\n", run_shell("if false; then cat <<A\nyes\nA\nelse cat <<B\nno\nB\nfi\n")
  end

  def test_heredoc_in_a_function_called_later
    assert_equal "in a\nin b\n", run_script("f() {\n  cat <<EOF\nin $1\nEOF\n}\nf a\nf b\n")
  end

  def test_two_heredocs_in_a_script
    assert_equal "a\nb\n", run_script("cat <<EOF\na\nEOF\ncat <<EOF\nb\nEOF\n")
  end
end
