# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# An array literal may spread its elements over several lines
class TestMultilineArrayLiteral < Test::Unit::TestCase
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

def test_array_literal
  check("arr=(\n  one\n  two\n); echo ${#arr[@]} ${arr[1]}\n", "2 two\n")
end
end
