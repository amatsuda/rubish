# frozen_string_literal: true

require_relative 'test_helper'

# The "[1] 12345" job notice belongs to interactive shells; scripts and
# `rubish -c` must not print it, as in bash
class TestBackgroundNoticeInteractiveOnly < Test::Unit::TestCase
  EXE = File.expand_path('../exe/rubish', __dir__)

  def test_no_job_notice_in_command_string_mode
    out = IO.popen([RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), EXE, '-c', 'true & wait; echo done'], err: %i[child out], &:read)
    assert_equal "done\n", out.gsub(/\e\[[0-9;?]*[A-Za-z]/, '')
  end

  def test_no_job_notice_in_script_mode
    Dir.mktmpdir('rubish_bg') do |dir|
      script = File.join(dir, 's.sh')
      File.write(script, "true &\nwait\necho done\n")
      out = IO.popen([RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), EXE, script], err: %i[child out], &:read)
      assert_equal "done\n", out
    end
  end
end
