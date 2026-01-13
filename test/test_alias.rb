# frozen_string_literal: true

require_relative 'test_helper'

class TestAlias < Test::Unit::TestCase
  def setup
    Rubish::Builtins.clear_aliases
  end

  def teardown
    Rubish::Builtins.clear_aliases
  end

  def test_define_alias
    Rubish::Builtins.run('alias', ['ll=ls -la'])
    assert_equal({'ll' => 'ls -la'}, Rubish::Builtins.aliases)
  end

  def test_define_alias_with_single_quotes
    Rubish::Builtins.run('alias', ["ll='ls -la'"])
    assert_equal({'ll' => 'ls -la'}, Rubish::Builtins.aliases)
  end

  def test_define_alias_with_double_quotes
    Rubish::Builtins.run('alias', ['ll="ls -la"'])
    assert_equal({'ll' => 'ls -la'}, Rubish::Builtins.aliases)
  end

  def test_define_multiple_aliases
    Rubish::Builtins.run('alias', ['ll=ls -la', 'g=git'])
    assert_equal({'ll' => 'ls -la', 'g' => 'git'}, Rubish::Builtins.aliases)
  end

  def test_unalias
    Rubish::Builtins.run('alias', ['ll=ls -la'])
    Rubish::Builtins.run('unalias', ['ll'])
    assert_equal({}, Rubish::Builtins.aliases)
  end

  def test_unalias_nonexistent
    output = capture_output { Rubish::Builtins.run('unalias', ['nonexistent']) }
    assert_match(/not found/, output)
  end

  def test_expand_alias
    Rubish::Builtins.run('alias', ['ll=ls -la'])
    result = Rubish::Builtins.expand_alias('ll')
    assert_equal 'ls -la', result
  end

  def test_expand_alias_with_args
    Rubish::Builtins.run('alias', ['ll=ls -la'])
    result = Rubish::Builtins.expand_alias('ll /tmp')
    assert_equal 'ls -la /tmp', result
  end

  def test_no_expand_for_non_alias
    result = Rubish::Builtins.expand_alias('ls -la')
    assert_equal 'ls -la', result
  end

  def test_empty_line_expand
    result = Rubish::Builtins.expand_alias('')
    assert_equal '', result
  end

  def test_alias_list
    Rubish::Builtins.run('alias', ['ll=ls -la', 'g=git'])
    output = capture_output { Rubish::Builtins.run('alias', []) }
    assert_match(/alias ll='ls -la'/, output)
    assert_match(/alias g='git'/, output)
  end

  def test_alias_show_specific
    Rubish::Builtins.run('alias', ['ll=ls -la'])
    output = capture_output { Rubish::Builtins.run('alias', ['ll']) }
    assert_match(/alias ll='ls -la'/, output)
  end

  def test_alias_show_nonexistent
    output = capture_output { Rubish::Builtins.run('alias', ['nonexistent']) }
    assert_match(/not found/, output)
  end

  def test_alias_overwrite
    Rubish::Builtins.run('alias', ['ll=ls -la'])
    Rubish::Builtins.run('alias', ['ll=ls -lah'])
    assert_equal({'ll' => 'ls -lah'}, Rubish::Builtins.aliases)
  end

  def test_alias_only_expands_first_word
    Rubish::Builtins.run('alias', ['g=git'])
    result = Rubish::Builtins.expand_alias('echo g')
    assert_equal 'echo g', result
  end

  # Test default aliases (like fish)
  def test_setup_default_aliases_sets_ls
    repl = Rubish::REPL.new
    repl.send(:setup_default_aliases)

    assert Rubish::Builtins.aliases.key?('ls'), 'ls alias should be set'
    if RUBY_PLATFORM =~ /darwin|bsd/i
      assert_equal 'ls -G', Rubish::Builtins.aliases['ls']
    else
      assert_equal 'ls --color=auto', Rubish::Builtins.aliases['ls']
    end
  end

  def test_setup_default_aliases_sets_ll
    repl = Rubish::REPL.new
    repl.send(:setup_default_aliases)

    assert Rubish::Builtins.aliases.key?('ll'), 'll alias should be set'
    if RUBY_PLATFORM =~ /darwin|bsd/i
      assert_equal 'ls -lG', Rubish::Builtins.aliases['ll']
    else
      assert_equal 'ls -l --color=auto', Rubish::Builtins.aliases['ll']
    end
  end

  def test_setup_default_aliases_sets_la
    repl = Rubish::REPL.new
    repl.send(:setup_default_aliases)

    assert Rubish::Builtins.aliases.key?('la'), 'la alias should be set'
    if RUBY_PLATFORM =~ /darwin|bsd/i
      assert_equal 'ls -laG', Rubish::Builtins.aliases['la']
    else
      assert_equal 'ls -la --color=auto', Rubish::Builtins.aliases['la']
    end
  end

  def test_setup_default_aliases_sets_grep
    repl = Rubish::REPL.new
    repl.send(:setup_default_aliases)

    assert Rubish::Builtins.aliases.key?('grep'), 'grep alias should be set'
    assert_equal 'grep --color=auto', Rubish::Builtins.aliases['grep']
  end

  def test_setup_default_aliases_does_not_overwrite_existing
    # Set custom aliases first
    Rubish::Builtins.aliases['ls'] = 'ls -la'
    Rubish::Builtins.aliases['grep'] = 'grep -n'

    repl = Rubish::REPL.new
    repl.send(:setup_default_aliases)

    # Should preserve the existing aliases
    assert_equal 'ls -la', Rubish::Builtins.aliases['ls']
    assert_equal 'grep -n', Rubish::Builtins.aliases['grep']
  end
end
