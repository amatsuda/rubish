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
    assert_equal '"~"', expand('"~"')
  end

  def test_tilde_path_in_double_quotes
    assert_equal '"~/Documents"', expand('"~/Documents"')
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

  def test_tilde_plus_pwd
    ENV['PWD'] = '/test/pwd'
    assert_equal '/test/pwd', expand('~+')
  end

  def test_tilde_plus_with_path
    ENV['PWD'] = '/test/pwd'
    assert_equal '/test/pwd/subdir', expand('~+/subdir')
  end

  def test_tilde_minus_oldpwd
    ENV['OLDPWD'] = '/old/path'
    assert_equal '/old/path', expand('~-')
  end

  def test_tilde_minus_with_path
    ENV['OLDPWD'] = '/old/path'
    assert_equal '/old/path/subdir', expand('~-/subdir')
  end

  def test_tilde_minus_no_oldpwd
    ENV.delete('OLDPWD')
    assert_equal '~-', expand('~-')
  end

  def test_tilde_plus_in_command
    ENV['PWD'] = '/current'
    assert_equal 'ls /current', expand('ls ~+')
  end

  def test_tilde_minus_in_command
    ENV['OLDPWD'] = '/previous'
    assert_equal 'cd /previous', expand('cd ~-')
  end

  def test_tilde_plus_not_followed_by_slash_or_space
    # ~+extra should expand ~ only, not ~+
    assert_match(/\+extra$/, expand('~+extra'))
  end

  def test_tilde_not_expanded_inside_double_quotes
    assert_equal '"no =~"', expand('"no =~"')
  end

  def test_tilde_not_expanded_after_equals_in_double_quotes
    assert_equal '"path=~"', expand('"path=~"')
  end

  def test_tilde_not_expanded_in_non_assignment_word
    # "echo x=~" looks like an assignment but isn't — tilde should stay literal.
    # bash mistakenly expands here; POSIX says don't. rubish matches POSIX.
    assert_equal 'echo x=~', expand('echo x=~')
  end

  def test_tilde_no_dynamic_assignment_expansion
    # Tilde in a string that becomes an assignment via eval/readonly "$binding"
    # should NOT expand at the point of initial string creation.
    assert_equal "binding='const=~/src'", expand("binding='const=~/src'")
  end
end
