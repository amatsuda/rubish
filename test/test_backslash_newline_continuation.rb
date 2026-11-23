# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# A backslash before a newline joins the two lines, outside single quotes
class TestBackslashNewlineContinuation < Test::Unit::TestCase
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

def test_backslash_continuation
  check("echo one \\\n  two \\\n  three\n", "one two three\n")
end

def test_backslash_newline_in_double_quotes
  check("echo \"a\\\nb\"\n", "ab\n")
end

def test_single_quotes_keep_the_backslash_and_newline
  check("echo 'a\\\nb'\n", "a\\\nb\n")
end
end
