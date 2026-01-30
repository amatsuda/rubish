# frozen_string_literal: true

require_relative 'test_helper'

class TestGLOBIGNORE < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_globignore_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def glob(pattern)
    @repl.send(:__glob, pattern)
  end

  # Basic GLOBIGNORE functionality

  def test_glob_without_globignore
    FileUtils.touch('file.txt')
    FileUtils.touch('file.o')
    FileUtils.touch('file.bak')
    ENV.delete('GLOBIGNORE')

    results = glob('file.*')

    assert_equal ['file.bak', 'file.o', 'file.txt'], results.sort
  end

  def test_globignore_single_pattern
    FileUtils.touch('main.c')
    FileUtils.touch('main.o')
    FileUtils.touch('helper.c')
    FileUtils.touch('helper.o')
    ENV['GLOBIGNORE'] = '*.o'

    results = glob('*')

    assert_includes results, 'main.c'
    assert_includes results, 'helper.c'
    assert_not_include results, 'main.o'
    assert_not_include results, 'helper.o'
  end

  def test_globignore_multiple_patterns
    FileUtils.touch('file.txt')
    FileUtils.touch('file.o')
    FileUtils.touch('file.bak')
    FileUtils.touch('file.tmp')
    ENV['GLOBIGNORE'] = '*.o:*.bak:*.tmp'

    results = glob('file.*')

    assert_equal ['file.txt'], results
  end

  def test_globignore_filters_directories_too
    FileUtils.mkdir('backup.bak')
    FileUtils.touch('file.bak')
    FileUtils.touch('file.txt')
    ENV['GLOBIGNORE'] = '*.bak'

    results = glob('*')

    assert_includes results, 'file.txt'
    assert_not_include results, 'file.bak'
    assert_not_include results, 'backup.bak'
  end

  def test_globignore_empty_string
    FileUtils.touch('file.txt')
    FileUtils.touch('file.o')
    ENV['GLOBIGNORE'] = ''

    results = glob('file.*')

    assert_equal ['file.o', 'file.txt'], results.sort
  end

  def test_globignore_empty_entries_ignored
    FileUtils.touch('file.txt')
    FileUtils.touch('file.o')
    FileUtils.touch('file.bak')
    ENV['GLOBIGNORE'] = '*.o::*.bak'  # Empty entry between colons

    results = glob('file.*')

    assert_equal ['file.txt'], results
  end

  def test_globignore_tilde_pattern
    FileUtils.touch('file.txt')
    FileUtils.touch('file.txt~')
    ENV['GLOBIGNORE'] = '*~'

    results = glob('file.*')

    assert_equal ['file.txt'], results
  end

  def test_globignore_with_subdirectory
    FileUtils.mkdir('subdir')
    FileUtils.touch('subdir/code.c')
    FileUtils.touch('subdir/code.o')
    ENV['GLOBIGNORE'] = '*.o'

    results = glob('subdir/*')

    assert_equal ['subdir/code.c'], results
  end

  def test_globignore_question_mark_pattern
    FileUtils.touch('file.c')
    FileUtils.touch('file.o')
    FileUtils.touch('file.h')
    FileUtils.touch('file.cc')  # Two character extension - not filtered
    ENV['GLOBIGNORE'] = '*.?'  # Single character extension

    results = glob('file.*')

    assert_equal ['file.cc'], results
  end

  def test_globignore_excludes_dot_and_dotdot_when_set
    FileUtils.touch('file.txt')
    ENV['GLOBIGNORE'] = '*.bak'  # Any GLOBIGNORE setting

    # Even with dotglob, . and .. should be excluded when GLOBIGNORE is set
    Rubish::Builtins.current_state.set_options['dotglob'] = true
    results = glob('*')
    Rubish::Builtins.current_state.set_options['dotglob'] = false

    assert_includes results, 'file.txt'
    assert_not_include results, '.'
    assert_not_include results, '..'
  end

  def test_globignore_with_full_path_pattern
    FileUtils.mkdir('build')
    FileUtils.touch('build/output.o')
    FileUtils.touch('build/output.exe')
    FileUtils.touch('src.c')
    ENV['GLOBIGNORE'] = 'build/*'

    results = glob('*')

    # build directory itself should be filtered
    assert_includes results, 'src.c'
    # build/* pattern should filter contents via path matching
  end

  def test_globignore_with_nullglob_returns_empty
    FileUtils.touch('file.o')
    FileUtils.touch('file.txt')
    ENV['GLOBIGNORE'] = '*.o:*.txt'
    Rubish::Builtins.current_state.set_options['nullglob'] = true

    results = glob('file.*')

    # All matches filtered + nullglob = empty array
    assert_equal [], results

    Rubish::Builtins.current_state.set_options['nullglob'] = false
  end

  def test_globignore_with_failglob_raises_error
    FileUtils.touch('file.o')
    FileUtils.touch('file.txt')
    ENV['GLOBIGNORE'] = '*.o:*.txt'
    Rubish::Builtins.current_state.set_options['failglob'] = true

    assert_raise(Rubish::FailglobError) do
      glob('file.*')
    end

    Rubish::Builtins.current_state.set_options['failglob'] = false
  end

  def test_globignore_returns_pattern_if_all_filtered
    FileUtils.touch('file.o')
    FileUtils.touch('file.bak')
    ENV['GLOBIGNORE'] = '*.o:*.bak'

    results = glob('file.*')

    # All matches filtered, and nullglob is off, so return original pattern
    assert_equal ['file.*'], results
  end

  # Pattern matching tests

  def test_globignore_star_matches_any
    FileUtils.touch('test.log')
    FileUtils.touch('debug.log')
    FileUtils.touch('output.txt')
    ENV['GLOBIGNORE'] = '*.log'

    results = glob('*')

    assert_includes results, 'output.txt'
    assert_not_include results, 'test.log'
    assert_not_include results, 'debug.log'
  end

  def test_globignore_matches_hidden_files
    FileUtils.touch('.hidden')
    FileUtils.touch('.config')
    FileUtils.touch('visible')
    ENV['GLOBIGNORE'] = '.*'

    Rubish::Builtins.current_state.set_options['dotglob'] = true
    results = glob('*')
    Rubish::Builtins.current_state.set_options['dotglob'] = false

    assert_includes results, 'visible'
    assert_not_include results, '.hidden'
    assert_not_include results, '.config'
  end

  # Integration tests

  def test_globignore_via_execute
    FileUtils.touch('script.sh')
    FileUtils.touch('script.sh~')
    FileUtils.touch('data.txt')
    ENV['GLOBIGNORE'] = '*~'

    output_file = File.join(@tempdir, 'output.txt')
    execute("echo * > #{output_file}")

    output = File.read(output_file).strip
    assert_includes output, 'script.sh'
    assert_includes output, 'data.txt'
    assert_not_include output, 'script.sh~'
  end

  def test_globignore_common_patterns
    FileUtils.touch('main.c')
    FileUtils.touch('main.o')
    FileUtils.touch('backup.bak')
    FileUtils.touch('temp.tmp')
    FileUtils.touch('notes.txt~')
    FileUtils.touch('code.pyc')
    ENV['GLOBIGNORE'] = '*.o:*.bak:*.tmp:*~:*.pyc'

    results = glob('*')

    assert_equal ['main.c'], results
  end
end
