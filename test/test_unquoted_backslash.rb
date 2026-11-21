# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# In an unquoted word a backslash quotes the next character and is removed:
# `echo \a` prints a. Inside double quotes it stays unless it precedes one of
# $ ` " \ or newline.
class TestUnquotedBackslash < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_bs') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_backslash_before_ordinary_character_is_removed
    assert_equal "a z q\n", run_and_read('echo \a \z \q')
  end

  def test_backslash_before_special_characters
    assert_equal "$HOME \\ \" *\n", run_and_read('echo \$HOME \\\\ \" \*')
  end

  def test_external_command_sees_the_unescaped_argument
    assert_equal "z\n", run_and_read('printf "%s\n" \z')
  end

  def test_double_quotes_keep_the_backslash_before_ordinary_characters
    assert_equal "x\\z y\\z\n", run_and_read(%q(echo "x\z" 'y\z'))
  end

  def test_lone_builtin_fast_path
    execute('bs_v=$(echo \a\z)')
    assert_equal 'az', get_shell_var('bs_v')
  end
end
