# frozen_string_literal: true

require_relative 'test_helper'

class TestGlob < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_glob_test')
    # Create test files
    FileUtils.touch(File.join(@tempdir, 'file1.txt'))
    FileUtils.touch(File.join(@tempdir, 'file2.txt'))
    FileUtils.touch(File.join(@tempdir, 'file3.rb'))
    FileUtils.touch(File.join(@tempdir, 'other.log'))
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # __glob helper tests
  def test_glob_expands_star
    matches = @repl.send(:__glob, File.join(@tempdir, '*.txt'))
    assert_equal 2, matches.length
    assert matches.all? { |m| m.end_with?('.txt') }
  end

  def test_glob_expands_question_mark
    matches = @repl.send(:__glob, File.join(@tempdir, 'file?.txt'))
    assert_equal 2, matches.length
  end

  def test_glob_expands_brackets
    matches = @repl.send(:__glob, File.join(@tempdir, 'file[12].txt'))
    assert_equal 2, matches.length
    assert matches.include?(File.join(@tempdir, 'file1.txt'))
    assert matches.include?(File.join(@tempdir, 'file2.txt'))
  end

  def test_glob_no_match_returns_pattern
    matches = @repl.send(:__glob, File.join(@tempdir, '*.xyz'))
    assert_equal 1, matches.length
    assert matches.first.end_with?('*.xyz')
  end

  # Codegen tests
  def test_codegen_glob_star
    tokens = Rubish::Lexer.new('echo *.txt').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__glob\("\*\.txt"\)/, code)
  end

  def test_codegen_glob_question
    tokens = Rubish::Lexer.new('ls file?.txt').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__glob\("file\?\.txt"\)/, code)
  end

  def test_codegen_glob_brackets
    tokens = Rubish::Lexer.new('ls file[12].txt').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__glob\("file\[12\]\.txt"\)/, code)
  end

  def test_codegen_single_quoted_no_glob
    tokens = Rubish::Lexer.new("echo '*.txt'").tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_no_match(/__glob/, code)
  end

  def test_codegen_double_quoted_no_glob
    tokens = Rubish::Lexer.new('echo "*.txt"').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_no_match(/__glob/, code)
  end

  # Execution tests
  def test_glob_star_execution
    Dir.chdir(@tempdir) do
      execute("echo *.txt > #{output_file}")
    end
    content = File.read(output_file)
    assert_match(/file1\.txt/, content)
    assert_match(/file2\.txt/, content)
  end

  def test_glob_question_execution
    Dir.chdir(@tempdir) do
      execute("echo file?.txt > #{output_file}")
    end
    content = File.read(output_file)
    assert_match(/file1\.txt/, content)
    assert_match(/file2\.txt/, content)
  end

  def test_glob_brackets_execution
    Dir.chdir(@tempdir) do
      execute("echo file[12].txt > #{output_file}")
    end
    content = File.read(output_file)
    assert_match(/file1\.txt/, content)
    assert_match(/file2\.txt/, content)
    assert_no_match(/file3/, content)
  end

  def test_glob_no_match_keeps_pattern
    execute("echo *.xyz > #{output_file}")
    content = File.read(output_file)
    assert_equal "*.xyz\n", content
  end

  def test_single_quoted_glob_not_expanded
    Dir.chdir(@tempdir) do
      execute("echo '*.txt' > #{output_file}")
    end
    assert_equal "*.txt\n", File.read(output_file)
  end

  def test_double_quoted_glob_not_expanded
    Dir.chdir(@tempdir) do
      execute("echo \"*.txt\" > #{output_file}")
    end
    assert_equal "*.txt\n", File.read(output_file)
  end

  def test_glob_with_variable_expansion
    ENV['EXT'] = 'txt'
    Dir.chdir(@tempdir) do
      execute("echo *.$EXT > #{output_file}")
    end
    content = File.read(output_file)
    assert_match(/file1\.txt/, content)
    assert_match(/file2\.txt/, content)
  end

  def test_glob_in_for_loop
    Dir.chdir(@tempdir) do
      execute("for f in *.txt; do echo $f >> #{output_file}; done")
    end
    content = File.read(output_file)
    lines = content.lines.map(&:chomp)
    assert lines.include?('file1.txt')
    assert lines.include?('file2.txt')
  end

  def test_glob_absolute_path
    execute("echo #{@tempdir}/*.txt > #{output_file}")
    content = File.read(output_file)
    assert_match(/file1\.txt/, content)
    assert_match(/file2\.txt/, content)
  end
end
