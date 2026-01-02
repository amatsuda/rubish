# frozen_string_literal: true

require_relative 'test_helper'

class TestHeredoc < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_heredoc_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_heredoc_token
    tokens = Rubish::Lexer.new('cat <<EOF').tokenize
    assert_equal :WORD, tokens[0].type
    assert_equal :HEREDOC, tokens[1].type
    assert_equal 'EOF', tokens[1].value
  end

  def test_heredoc_indent_token
    tokens = Rubish::Lexer.new('cat <<-EOF').tokenize
    assert_equal :WORD, tokens[0].type
    assert_equal :HEREDOC_INDENT, tokens[1].type
    assert_equal 'EOF', tokens[1].value
  end

  def test_heredoc_quoted_single
    tokens = Rubish::Lexer.new("cat <<'EOF'").tokenize
    assert_equal :HEREDOC, tokens[1].type
    assert_equal 'EOF:quoted', tokens[1].value
  end

  def test_heredoc_quoted_double
    tokens = Rubish::Lexer.new('cat <<"EOF"').tokenize
    assert_equal :HEREDOC, tokens[1].type
    assert_equal 'EOF:quoted', tokens[1].value
  end

  def test_herestring_token
    tokens = Rubish::Lexer.new('cat <<< hello').tokenize
    assert_equal :WORD, tokens[0].type
    assert_equal :HERESTRING, tokens[1].type
    assert_equal 'hello', tokens[1].value
  end

  def test_herestring_quoted
    tokens = Rubish::Lexer.new('cat <<< "hello world"').tokenize
    assert_equal :HERESTRING, tokens[1].type
    assert_equal '"hello world"', tokens[1].value
  end

  # Parser tests
  def test_heredoc_parsing
    tokens = Rubish::Lexer.new('cat <<EOF').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Heredoc, ast
    assert_equal 'EOF', ast.delimiter
    assert_equal true, ast.expand
    assert_equal false, ast.strip_tabs
  end

  def test_heredoc_indent_parsing
    tokens = Rubish::Lexer.new('cat <<-EOF').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Heredoc, ast
    assert_equal 'EOF', ast.delimiter
    assert_equal true, ast.expand
    assert_equal true, ast.strip_tabs
  end

  def test_heredoc_quoted_parsing
    tokens = Rubish::Lexer.new("cat <<'EOF'").tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Heredoc, ast
    assert_equal 'EOF', ast.delimiter
    assert_equal false, ast.expand
  end

  def test_herestring_parsing
    tokens = Rubish::Lexer.new('cat <<< hello').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Herestring, ast
    assert_equal 'hello', ast.string
  end

  # Codegen tests
  def test_heredoc_codegen
    tokens = Rubish::Lexer.new('cat <<EOF').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__heredoc/, code)
    assert_match(/"EOF"/, code)
  end

  def test_herestring_codegen
    tokens = Rubish::Lexer.new('cat <<< hello').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__herestring/, code)
  end

  # Herestring execution tests (can run without multi-line input)
  def test_herestring_simple
    execute("cat <<< hello > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_herestring_single_quoted
    execute("cat <<< 'hello world' > #{output_file}")
    assert_equal "hello world\n", File.read(output_file)
  end

  def test_herestring_double_quoted
    ENV['NAME'] = 'World'
    execute("cat <<< \"Hello $NAME\" > #{output_file}")
    assert_equal "Hello World\n", File.read(output_file)
  end

  def test_herestring_in_pipeline
    execute("cat <<< HELLO | tr A-Z a-z > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  # Script-based heredoc tests
  def test_heredoc_in_script
    script = File.join(@tempdir, 'heredoc.sh')
    File.write(script, <<~SCRIPT)
      cat <<EOF > #{output_file}
      hello
      world
      EOF
    SCRIPT

    execute("source #{script}")
    assert_equal "hello\nworld\n", File.read(output_file)
  end

  def test_heredoc_with_variable_expansion
    script = File.join(@tempdir, 'heredoc_var.sh')
    File.write(script, <<~SCRIPT)
      export NAME=Alice
      cat <<EOF > #{output_file}
      Hello $NAME
      EOF
    SCRIPT

    execute("source #{script}")
    assert_equal "Hello Alice\n", File.read(output_file)
  end

  def test_heredoc_quoted_no_expansion
    script = File.join(@tempdir, 'heredoc_quoted.sh')
    File.write(script, <<~SCRIPT)
      export NAME=Alice
      cat <<'EOF' > #{output_file}
      Hello $NAME
      EOF
    SCRIPT

    execute("source #{script}")
    assert_equal "Hello $NAME\n", File.read(output_file)
  end

  def test_heredoc_indent_strip_tabs
    script = File.join(@tempdir, 'heredoc_indent.sh')
    File.write(script, <<~SCRIPT)
      cat <<-EOF > #{output_file}
      \thello
      \tworld
      \tEOF
    SCRIPT

    execute("source #{script}")
    assert_equal "hello\nworld\n", File.read(output_file)
  end

  def test_heredoc_in_pipeline_script
    script = File.join(@tempdir, 'heredoc_pipe.sh')
    File.write(script, <<~SCRIPT)
      cat <<EOF | tr a-z A-Z > #{output_file}
      hello
      world
      EOF
    SCRIPT

    execute("source #{script}")
    assert_equal "HELLO\nWORLD\n", File.read(output_file)
  end

  def test_heredoc_multiline_content
    script = File.join(@tempdir, 'heredoc_multi.sh')
    File.write(script, <<~SCRIPT)
      cat <<END > #{output_file}
      line 1
      line 2
      line 3
      END
    SCRIPT

    execute("source #{script}")
    assert_equal "line 1\nline 2\nline 3\n", File.read(output_file)
  end

  def test_heredoc_empty_content
    script = File.join(@tempdir, 'heredoc_empty.sh')
    File.write(script, <<~SCRIPT)
      cat <<EOF > #{output_file}
      EOF
    SCRIPT

    execute("source #{script}")
    assert_equal '', File.read(output_file)
  end

  def test_heredoc_preserves_whitespace
    script = File.join(@tempdir, 'heredoc_ws.sh')
    File.write(script, <<~SCRIPT)
      cat <<EOF > #{output_file}
        indented
          more indented
      EOF
    SCRIPT

    execute("source #{script}")
    assert_equal "  indented\n    more indented\n", File.read(output_file)
  end

  def test_heredoc_special_chars
    script = File.join(@tempdir, 'heredoc_special.sh')
    File.write(script, <<~SCRIPT)
      cat <<EOF > #{output_file}
      line with * and ? and [brackets]
      EOF
    SCRIPT

    execute("source #{script}")
    assert_equal "line with * and ? and [brackets]\n", File.read(output_file)
  end

  # Helper tests
  def test_detect_heredoc
    assert_equal ['EOF', false], Rubish::Builtins.detect_heredoc('cat <<EOF')
    assert_equal ['END', false], Rubish::Builtins.detect_heredoc('cat << END')
    assert_equal ['EOF', true], Rubish::Builtins.detect_heredoc('cat <<-EOF')
    assert_equal ['MARKER', false], Rubish::Builtins.detect_heredoc("cat <<'MARKER'")
    assert_equal ['MARKER', false], Rubish::Builtins.detect_heredoc('cat <<"MARKER"')
    assert_nil Rubish::Builtins.detect_heredoc('cat <<< hello')  # herestring
    assert_nil Rubish::Builtins.detect_heredoc('echo hello')     # no heredoc
  end
end
