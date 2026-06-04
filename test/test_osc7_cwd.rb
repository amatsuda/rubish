# frozen_string_literal: true

require_relative 'test_helper'

# notify_terminal_of_cwd emits OSC 7 so terminal emulators can open a
# new tab in the same cwd. The URI inside must be percent-encoded
# byte-wise per RFC 3986; encoding by Unicode character produces
# malformed sequences (e.g. `%3042` for U+3042) that Terminal.app
# can't resolve, so cmd-T falls back to ~.
class TestOsc7Cwd < Test::Unit::TestCase
  def setup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_osc7_test')
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
  end

  # Run notify_terminal_of_cwd with $stdout swapped for a StringIO that
  # claims to be a TTY (so the early-return guard doesn't fire), and
  # return the captured bytes.
  def capture_notify
    original_stdout = $stdout
    $stdout = StringIO.new
    $stdout.define_singleton_method(:tty?) { true }
    Rubish::Builtins.notify_terminal_of_cwd
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def extract_path(osc)
    # OSC 7: ESC ] 7 ; file://<host><path> BEL
    osc =~ %r{\A\e\]7;file://[^/]*(.*)\a\z} or flunk "not OSC 7: #{osc.inspect}"
    $1
  end

  def test_returns_early_when_stdout_is_not_a_tty
    out = StringIO.new
    original = $stdout
    $stdout = out
    Rubish::Builtins.notify_terminal_of_cwd
    assert_empty out.string
  ensure
    $stdout = original
  end

  def test_ascii_path_encoded_unchanged
    Dir.chdir(@tempdir)
    assert_equal File.realpath(@tempdir), extract_path(capture_notify)
  end

  def test_path_with_space_is_percent_encoded
    FileUtils.mkdir(File.join(@tempdir, 'a b'))
    Dir.chdir(File.join(@tempdir, 'a b'))
    expected = File.realpath(File.join(@tempdir, 'a b')).sub(' ', '%20')
    assert_equal expected, extract_path(capture_notify)
  end

  # The bug: U+3042 (HIRAGANA LETTER A) used to come out as %3042
  # instead of %E3%81%82.
  def test_multibyte_path_is_percent_encoded_byte_wise
    multibyte_dir = File.join(@tempdir, 'あ')
    FileUtils.mkdir(multibyte_dir)
    Dir.chdir(multibyte_dir)

    path = extract_path(capture_notify)
    refute_match(/%3042/, path)
    assert_match(/%E3%81%82\z/, path)
  end
end
