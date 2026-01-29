# frozen_string_literal: true

require_relative 'test_helper'

class TestEXECIGNORE < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_execignore_test')
    @bindir1 = File.join(@tempdir, 'bin1')
    @bindir2 = File.join(@tempdir, 'bin2')
    FileUtils.mkdir_p(@bindir1)
    FileUtils.mkdir_p(@bindir2)
    ENV['PATH'] = "#{@bindir1}:#{@bindir2}:#{ENV['PATH']}"
    # Clear hash
    Rubish::Builtins.clear_hash
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def create_executable(path)
    File.write(path, "#!/bin/sh\necho #{File.basename(path)}")
    File.chmod(0755, path)
  end

  # Basic EXECIGNORE functionality

  def test_execignore_not_set_finds_all
    create_executable(File.join(@bindir1, 'mycommand'))
    ENV.delete('EXECIGNORE')

    result = Rubish::Builtins.find_in_path('mycommand')

    assert_equal File.join(@bindir1, 'mycommand'), result
  end

  def test_execignore_empty_finds_all
    create_executable(File.join(@bindir1, 'mycommand'))
    ENV['EXECIGNORE'] = ''

    result = Rubish::Builtins.find_in_path('mycommand')

    assert_equal File.join(@bindir1, 'mycommand'), result
  end

  def test_execignore_ignores_matching_basename
    create_executable(File.join(@bindir1, 'ignored_cmd'))
    ENV['EXECIGNORE'] = 'ignored_cmd'

    result = Rubish::Builtins.find_in_path('ignored_cmd')

    assert_nil result
  end

  def test_execignore_ignores_matching_pattern
    create_executable(File.join(@bindir1, 'test_cmd'))
    create_executable(File.join(@bindir1, 'good_cmd'))
    ENV['EXECIGNORE'] = 'test_*'

    result_test = Rubish::Builtins.find_in_path('test_cmd')
    result_good = Rubish::Builtins.find_in_path('good_cmd')

    assert_nil result_test
    assert_equal File.join(@bindir1, 'good_cmd'), result_good
  end

  def test_execignore_multiple_patterns
    create_executable(File.join(@bindir1, 'ignored1'))
    create_executable(File.join(@bindir1, 'ignored2'))
    create_executable(File.join(@bindir1, 'allowed'))
    ENV['EXECIGNORE'] = 'ignored1:ignored2'

    assert_nil Rubish::Builtins.find_in_path('ignored1')
    assert_nil Rubish::Builtins.find_in_path('ignored2')
    assert_equal File.join(@bindir1, 'allowed'), Rubish::Builtins.find_in_path('allowed')
  end

  def test_execignore_wildcard_pattern
    create_executable(File.join(@bindir1, 'bad_cmd1'))
    create_executable(File.join(@bindir1, 'bad_cmd2'))
    create_executable(File.join(@bindir1, 'good_cmd'))
    ENV['EXECIGNORE'] = 'bad_*'

    assert_nil Rubish::Builtins.find_in_path('bad_cmd1')
    assert_nil Rubish::Builtins.find_in_path('bad_cmd2')
    assert_equal File.join(@bindir1, 'good_cmd'), Rubish::Builtins.find_in_path('good_cmd')
  end

  def test_execignore_matches_full_path
    create_executable(File.join(@bindir1, 'mycommand'))
    ENV['EXECIGNORE'] = "#{@bindir1}/*"

    result = Rubish::Builtins.find_in_path('mycommand')

    assert_nil result
  end

  def test_execignore_skips_first_match_finds_second
    create_executable(File.join(@bindir1, 'mycmd'))
    create_executable(File.join(@bindir2, 'mycmd'))
    ENV['EXECIGNORE'] = "#{@bindir1}/*"

    result = Rubish::Builtins.find_in_path('mycmd')

    # First one is ignored, second one should be found
    assert_equal File.join(@bindir2, 'mycmd'), result
  end

  # find_all_in_path tests

  def test_find_all_ignores_matching
    create_executable(File.join(@bindir1, 'cmd'))
    create_executable(File.join(@bindir2, 'cmd'))
    ENV['EXECIGNORE'] = "#{@bindir1}/*"

    results = Rubish::Builtins.find_all_in_path('cmd')

    assert_equal 1, results.length
    assert_equal File.join(@bindir2, 'cmd'), results[0]
  end

  def test_find_all_returns_all_without_execignore
    create_executable(File.join(@bindir1, 'cmd'))
    create_executable(File.join(@bindir2, 'cmd'))
    ENV.delete('EXECIGNORE')

    results = Rubish::Builtins.find_all_in_path('cmd')

    assert_equal 2, results.length
  end

  # execignore? helper tests

  def test_execignore_helper_returns_false_when_not_set
    ENV.delete('EXECIGNORE')
    assert_equal false, Rubish::Builtins.execignore?('/usr/bin/ls')
  end

  def test_execignore_helper_returns_false_when_empty
    ENV['EXECIGNORE'] = ''
    assert_equal false, Rubish::Builtins.execignore?('/usr/bin/ls')
  end

  def test_execignore_helper_matches_basename
    ENV['EXECIGNORE'] = 'ls'
    assert_equal true, Rubish::Builtins.execignore?('/usr/bin/ls')
  end

  def test_execignore_helper_matches_full_path
    ENV['EXECIGNORE'] = '/usr/bin/*'
    assert_equal true, Rubish::Builtins.execignore?('/usr/bin/ls')
  end

  def test_execignore_helper_no_match
    ENV['EXECIGNORE'] = 'other_cmd'
    assert_equal false, Rubish::Builtins.execignore?('/usr/bin/ls')
  end

  def test_execignore_empty_pattern_ignored
    ENV['EXECIGNORE'] = ':ls:'  # Empty patterns should be ignored
    assert_equal true, Rubish::Builtins.execignore?('/usr/bin/ls')
  end

  # Integration with type/which builtins (via direct Builtins calls)

  def test_type_builtin_respects_execignore
    create_executable(File.join(@bindir1, 'testcmd'))
    ENV['EXECIGNORE'] = 'testcmd'

    # Capture stdout
    output = capture_stdout { Rubish::Builtins.type(['testcmd']) }

    assert_match(/not found/, output)
  end

  def test_which_builtin_respects_execignore
    create_executable(File.join(@bindir1, 'testcmd'))
    ENV['EXECIGNORE'] = 'testcmd'

    output = capture_stdout { Rubish::Builtins.which(['testcmd']) }

    assert_match(/not found/, output)
  end

  def test_which_all_builtin_respects_execignore
    create_executable(File.join(@bindir1, 'testcmd'))
    create_executable(File.join(@bindir2, 'testcmd'))
    ENV['EXECIGNORE'] = "#{@bindir1}/*"

    output = capture_stdout { Rubish::Builtins.which(['-a', 'testcmd']) }

    assert_not_include output, @bindir1
    assert_include output, File.join(@bindir2, 'testcmd')
  end

  # Hash interaction tests

  def test_hash_lookup_with_execignore
    create_executable(File.join(@bindir1, 'hashtest'))
    ENV.delete('EXECIGNORE')

    # Manually store to hash (simulating what resolve_command_path does)
    full_path = File.join(@bindir1, 'hashtest')
    Rubish::Builtins.hash_store('hashtest', full_path)
    cached = Rubish::Builtins.hash_lookup('hashtest')
    assert_not_nil cached

    # Now set EXECIGNORE to match
    ENV['EXECIGNORE'] = 'hashtest'

    # find_in_path should ignore the command even though path is cached
    # (the hash is not used by find_in_path, but this tests that
    # EXECIGNORE filtering works regardless of hash state)
    result = Rubish::Builtins.find_in_path('hashtest')
    assert_nil result
  end

  # Path with slash tests

  def test_execignore_ignores_absolute_path
    exe_path = File.join(@bindir1, 'testcmd')
    create_executable(exe_path)
    ENV['EXECIGNORE'] = 'testcmd'

    result = Rubish::Builtins.find_in_path(exe_path)

    assert_nil result
  end

  def test_execignore_respects_absolute_path_pattern
    exe_path = File.join(@bindir1, 'testcmd')
    create_executable(exe_path)
    ENV['EXECIGNORE'] = "#{@bindir1}/*"

    result = Rubish::Builtins.find_in_path(exe_path)

    assert_nil result
  end

  def test_absolute_path_not_matched_by_pattern
    exe_path = File.join(@bindir1, 'testcmd')
    create_executable(exe_path)
    ENV['EXECIGNORE'] = "#{@bindir2}/*"

    result = Rubish::Builtins.find_in_path(exe_path)

    assert_equal exe_path, result
  end
end
