# frozen_string_literal: true

require_relative 'test_helper'

class TestLexer < Test::Unit::TestCase
  def tokenize(input)
    Rubish::Lexer.new(input).tokenize
  end

  def test_simple_command
    tokens = tokenize('ls')
    assert_equal 1, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal 'ls', tokens[0].value
  end

  def test_command_with_args
    tokens = tokenize('ls -la /tmp')
    assert_equal 3, tokens.length
    assert_equal ['ls', '-la', '/tmp'], tokens.map(&:value)
  end

  def test_pipe
    tokens = tokenize('ls | grep foo')
    assert_equal 4, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :PIPE, tokens[1].type
    assert_equal '|', tokens[1].value
    assert_equal :WORD, tokens[2].type
  end

  def test_redirect_out
    tokens = tokenize('echo hello > /tmp/file')
    assert_equal 4, tokens.length
    assert_equal :REDIRECT_OUT, tokens[2].type
    assert_equal '>', tokens[2].value
  end

  def test_redirect_append
    tokens = tokenize('echo hello >> /tmp/file')
    assert_equal 4, tokens.length
    assert_equal :REDIRECT_APPEND, tokens[2].type
    assert_equal '>>', tokens[2].value
  end

  def test_redirect_in
    tokens = tokenize('cat < /tmp/file')
    assert_equal 3, tokens.length
    assert_equal :REDIRECT_IN, tokens[1].type
  end

  def test_semicolon
    tokens = tokenize('echo a; echo b')
    assert_equal 5, tokens.length
    assert_equal :SEMICOLON, tokens[2].type
  end

  def test_ampersand
    tokens = tokenize('sleep 10 &')
    assert_equal 3, tokens.length
    assert_equal :AMPERSAND, tokens[2].type
  end

  def test_double_quoted_string
    tokens = tokenize('echo "hello world"')
    assert_equal 2, tokens.length
    assert_equal '"hello world"', tokens[1].value
  end

  def test_single_quoted_string
    tokens = tokenize("echo 'hello world'")
    assert_equal 2, tokens.length
    assert_equal "'hello world'", tokens[1].value
  end

  # New tests for parser edge cases

  # Test |& (pipe both stdout and stderr)
  def test_pipe_both
    tokens = tokenize('cmd1 |& cmd2')
    assert_equal 3, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :PIPE_BOTH, tokens[1].type
    assert_equal '|&', tokens[1].value
    assert_equal :WORD, tokens[2].type
  end

  # Test ;& (case fall-through)
  def test_case_fall
    tokens = tokenize(';&')
    assert_equal 1, tokens.length
    assert_equal :CASE_FALL, tokens[0].type
    assert_equal ';&', tokens[0].value
  end

  # Test ;;& (case continue)
  def test_case_cont
    tokens = tokenize(';;&')
    assert_equal 1, tokens.length
    assert_equal :CASE_CONT, tokens[0].type
    assert_equal ';;&', tokens[0].value
  end

  # Test ;; (double semi)
  def test_double_semi
    tokens = tokenize(';;')
    assert_equal 1, tokens.length
    assert_equal :DOUBLE_SEMI, tokens[0].type
    assert_equal ';;', tokens[0].value
  end

  # Test case with fall-through
  def test_case_with_fall_through_tokens
    tokens = tokenize('case x in a) echo a ;& b) echo b ;; esac')
    types = tokens.map(&:type)
    assert_includes types, :CASE_FALL
    assert_includes types, :DOUBLE_SEMI
  end

  # Test case with continue
  def test_case_with_continue_tokens
    tokens = tokenize('case x in a) echo a ;;& b) echo b ;; esac')
    types = tokens.map(&:type)
    assert_includes types, :CASE_CONT
    assert_includes types, :DOUBLE_SEMI
  end

  # Ensure ;;& and ;& don't conflict with each other
  def test_case_terminators_no_conflict
    tokens = tokenize(';& ;;& ;;')
    assert_equal 3, tokens.length
    assert_equal :CASE_FALL, tokens[0].type
    assert_equal :CASE_CONT, tokens[1].type
    assert_equal :DOUBLE_SEMI, tokens[2].type
  end

  # Test path vs regexp distinction

  # Path with trailing slash should be WORD, not REGEXP
  def test_path_with_trailing_slash
    tokens = tokenize('ls /bin/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :WORD, tokens[1].type
    assert_equal '/bin/', tokens[1].value
  end

  # Absolute path without trailing slash should be WORD
  def test_absolute_path
    tokens = tokenize('ls /bin')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/bin', tokens[1].value
  end

  # Relative path with ./ prefix and trailing slash should be WORD
  def test_relative_path_with_trailing_slash
    tokens = tokenize('ls ./bin/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal './bin/', tokens[1].value
  end

  # Regexp with metacharacters should be REGEXP
  def test_regexp_with_metacharacters
    tokens = tokenize('grep /foo.*bar/')
    assert_equal 2, tokens.length
    assert_equal :REGEXP, tokens[1].type
    assert_equal '/foo.*bar/', tokens[1].value
  end

  # Regexp with anchors should be REGEXP
  def test_regexp_with_anchors
    tokens = tokenize('grep /^start/')
    assert_equal 2, tokens.length
    assert_equal :REGEXP, tokens[1].type
    assert_equal '/^start/', tokens[1].value
  end

  # Path-like content should be WORD even if it looks like a regexp
  def test_simple_path_not_regexp
    tokens = tokenize('cat /etc/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/etc/', tokens[1].value
  end

  # Multi-level path should be WORD
  def test_multi_level_path
    tokens = tokenize('ls /usr/local/bin')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/usr/local/bin', tokens[1].value
  end

  # Multi-level path with trailing slash should be WORD (regression test)
  def test_multi_level_path_with_trailing_slash
    tokens = tokenize('cd /opt/homebrew/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :WORD, tokens[1].type
    assert_equal '/opt/homebrew/', tokens[1].value
  end

  # Deep path with trailing slash should be WORD
  def test_deep_path_with_trailing_slash
    tokens = tokenize('ls /usr/local/Cellar/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/usr/local/Cellar/', tokens[1].value
  end

  # Path with hyphen should be WORD
  def test_path_with_hyphen
    tokens = tokenize('cat /var/log/my-app/errors.log')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/var/log/my-app/errors.log', tokens[1].value
  end

  # Path with underscore should be WORD
  def test_path_with_underscore
    tokens = tokenize('ls /home/user/my_project/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/home/user/my_project/', tokens[1].value
  end

  # Path with dots should be WORD
  def test_path_with_dots
    tokens = tokenize('cat /etc/nginx/sites-enabled/example.com.conf')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
  end

  # Regexp with capture groups should be REGEXP
  def test_regexp_with_capture_groups
    tokens = tokenize('grep /(foo|bar)/')
    assert_equal 2, tokens.length
    assert_equal :REGEXP, tokens[1].type
  end

  # Regexp with character class should be REGEXP
  def test_regexp_with_character_class
    tokens = tokenize('grep /[a-z]+/')
    assert_equal 2, tokens.length
    assert_equal :REGEXP, tokens[1].type
  end

  # Regexp with quantifiers should be REGEXP
  def test_regexp_with_quantifiers
    tokens = tokenize('grep /fo+ba?r/')
    assert_equal 2, tokens.length
    assert_equal :REGEXP, tokens[1].type
  end
end
