# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Statements that span lines in a script and in a -c string: a function body
# on the next line, a subshell across lines, a heredoc that is not the
# line's first command
class TestMultilineScriptStatements < Test::Unit::TestCase
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

def test_function_body_on_the_next_line
  check("f()\n{\n  echo multi\n}\nf\n", "multi\n")
end

def test_subshell_across_lines
  check("(\necho a\necho b\n)\n", "a\nb\n")
end

def test_heredoc_after_another_command
  check("echo first; cat <<EOF\ndoc\nEOF\necho last\n", "first\ndoc\nlast\n")
end
end
