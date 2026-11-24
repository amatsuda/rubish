# frozen_string_literal: true

require_relative 'test_helper'

# `<>file` opens the file for reading and writing (bash)
class TestReadWriteRedirection < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      IO.popen([exe, '-c', script, err: %i[child out]], chdir: dir, &:read)
    end
  end

  def test_exec_with_a_descriptor
    assert_equal "data\ndata\n", run_shell('exec 3<>f; echo data >&3; exec 3>&-; cat f; exec 4<>f; read l <&4; echo "$l"; exec 4<&-')
  end

  def test_on_stdin
    assert_equal "x\ny\ny\n", run_shell('echo x > f; cat <>f; echo y 0<>g; cat g; echo y')
  end
end
