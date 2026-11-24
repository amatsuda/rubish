# frozen_string_literal: true

require_relative 'test_helper'

# `rubish -c text` reads the text a statement at a time, as bash does, so a
# line can turn on an option that the parsing of the next line relies on
class TestCommandStringReadIncrementally < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir { |dir| IO.popen([exe, '-c', script, err: %i[child out]], chdir: dir, &:read) }
  end

  def test_extglob_enabled_on_the_previous_line
    assert_equal "plus\nneg\n1\n", run_shell("shopt -s extglob\ncase abc in +([a-c])) echo plus;; esac; case abd in !(abc)) echo neg;; esac\necho !(nosuch*) | wc -w | tr -d ' '")
  end

  def test_function_body_on_the_next_lines
    assert_equal "multi\n", run_shell("f()\n{\n  echo multi\n}\nf")
  end

  def test_alias_defined_on_the_previous_line
    assert_equal "hi\n", run_shell("shopt -s expand_aliases\nalias x=echo\nx hi")
  end
end
