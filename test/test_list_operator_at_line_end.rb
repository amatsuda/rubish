# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# `&&`, `||`, `|` and `|&` at the end of a line continue the statement on the next
class TestListOperatorAtLineEnd < Test::Unit::TestCase
def exe
  File.expand_path('../exe/rubish', __dir__)
end

# Both as a script file and as a -c string
def check(script, expected)
  Dir.mktmpdir do |dir|
    path = File.join(dir, 's.sh')
    File.write(path, script)
    assert_equal expected, IO.popen([exe, path, err: File::NULL], &:read), 'as a script'
  end
  assert_equal expected, IO.popen([exe, '-c', script, err: File::NULL], &:read), 'as a -c string'
end

def test_and_operator_at_end_of_line
  check("true &&\necho and\n", "and\n")
end

def test_or_operator_at_end_of_line
  check("false ||\necho or\n", "or\n")
end

def test_pipe_at_end_of_line
  check("echo piped |\ncat\n", "piped\n")
end

def test_pipe_both_at_end_of_line
  check("{ echo out; echo err >&2; } |&\nwc -l | tr -d ' '\n", "2\n")
end
end
