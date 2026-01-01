# frozen_string_literal: true

require_relative 'test_helper'

class TestTildeExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def expand(line)
    @repl.send(:expand_tilde, line)
  end

  def test_simple_tilde
    assert_equal Dir.home, expand('~')
  end

  def test_tilde_with_path
    assert_equal "#{Dir.home}/Documents", expand('~/Documents')
  end

  def test_tilde_in_command
    assert_equal "ls #{Dir.home}", expand('ls ~')
  end

  def test_tilde_with_path_in_command
    assert_equal "cd #{Dir.home}/projects", expand('cd ~/projects')
  end

  def test_multiple_tildes
    assert_equal "cp #{Dir.home}/a #{Dir.home}/b", expand('cp ~/a ~/b')
  end

  def test_tilde_user
    # Test with current user
    current_user = ENV['USER']
    assert_equal Dir.home(current_user), expand("~#{current_user}")
  end

  def test_tilde_user_with_path
    current_user = ENV['USER']
    assert_equal "#{Dir.home(current_user)}/Documents", expand("~#{current_user}/Documents")
  end

  def test_tilde_unknown_user
    # Unknown user should be kept literal
    assert_equal '~nonexistentuser12345', expand('~nonexistentuser12345')
  end

  def test_tilde_in_single_quotes
    assert_equal "'~'", expand("'~'")
  end

  def test_tilde_path_in_single_quotes
    assert_equal "'~/Documents'", expand("'~/Documents'")
  end

  def test_tilde_in_double_quotes
    assert_equal "\"#{Dir.home}\"", expand('"~"')
  end

  def test_tilde_path_in_double_quotes
    assert_equal "\"#{Dir.home}/Documents\"", expand('"~/Documents"')
  end

  def test_tilde_not_at_word_start
    # ~ in middle of word should not expand
    assert_equal 'foo~bar', expand('foo~bar')
  end

  def test_tilde_after_equals
    # Common in export VAR=~/path
    assert_equal "PATH=#{Dir.home}/bin", expand('PATH=~/bin')
  end

  def test_tilde_after_colon
    # Common in PATH-like variables
    assert_equal "/usr/bin:#{Dir.home}/bin", expand('/usr/bin:~/bin')
  end

  def test_no_tilde
    assert_equal 'echo hello', expand('echo hello')
  end

  def test_tilde_root_user
    # Test ~root if it exists on the system
    begin
      root_home = Dir.home('root')
      assert_equal root_home, expand('~root')
    rescue ArgumentError
      # root user doesn't exist on this system, skip
      omit 'root user not available on this system'
    end
  end
end
