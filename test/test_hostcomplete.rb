# frozen_string_literal: true

require_relative 'test_helper'

class TestHostcomplete < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_hostcomplete_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    @original_hostfile = ENV['HOSTFILE']
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
    ENV['HOSTFILE'] = @original_hostfile
  end

  def complete_hostname(prefix)
    @repl.send(:complete_hostname, prefix)
  end

  # hostcomplete is enabled by default
  def test_hostcomplete_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('hostcomplete')
  end

  def test_hostcomplete_can_be_disabled
    execute('shopt -u hostcomplete')
    assert_false Rubish::Builtins.shopt_enabled?('hostcomplete')
  end

  def test_hostcomplete_can_be_enabled
    execute('shopt -u hostcomplete')
    execute('shopt -s hostcomplete')
    assert Rubish::Builtins.shopt_enabled?('hostcomplete')
  end

  # Test complete_hostname method with HOSTFILE
  def test_complete_hostname_from_hostfile
    # Create a test hosts file
    hosts_file = File.join(@tempdir, 'testhosts')
    File.write(hosts_file, <<~HOSTS)
      # Test hosts file
      127.0.0.1 localhost
      192.168.1.1 myserver.local myserver
      10.0.0.1 testhost.example.com testhost
      10.0.0.2 testbox.example.com testbox
    HOSTS

    ENV['HOSTFILE'] = hosts_file

    # Test completion with prefix
    results = complete_hostname('test')
    assert_includes results, 'testhost.example.com'
    assert_includes results, 'testhost'
    assert_includes results, 'testbox.example.com'
    assert_includes results, 'testbox'
  end

  def test_complete_hostname_empty_prefix
    hosts_file = File.join(@tempdir, 'testhosts')
    File.write(hosts_file, <<~HOSTS)
      127.0.0.1 localhost
      192.168.1.1 myserver
    HOSTS

    ENV['HOSTFILE'] = hosts_file

    results = complete_hostname('')
    assert_includes results, 'localhost'
    assert_includes results, 'myserver'
  end

  def test_complete_hostname_no_match
    hosts_file = File.join(@tempdir, 'testhosts')
    File.write(hosts_file, <<~HOSTS)
      127.0.0.1 localhost
    HOSTS

    ENV['HOSTFILE'] = hosts_file

    results = complete_hostname('xyz')
    assert_empty results
  end

  def test_complete_hostname_ignores_comments
    hosts_file = File.join(@tempdir, 'testhosts')
    File.write(hosts_file, <<~HOSTS)
      # This is a comment with xyzcommenthost
      127.0.0.1 xyzrealhost # inline comment with xyzfakehost
    HOSTS

    ENV['HOSTFILE'] = hosts_file

    results = complete_hostname('xyz')
    assert_includes results, 'xyzrealhost'
    refute_includes results, 'xyzcommenthost'
    refute_includes results, 'xyzfakehost'
  end

  def test_complete_hostname_skips_empty_lines
    hosts_file = File.join(@tempdir, 'testhosts')
    File.write(hosts_file, <<~HOSTS)
      127.0.0.1 host1


      192.168.1.1 host2
    HOSTS

    ENV['HOSTFILE'] = hosts_file

    results = complete_hostname('host')
    assert_equal 2, results.length
    assert_includes results, 'host1'
    assert_includes results, 'host2'
  end

  def test_complete_hostname_multiple_aliases
    hosts_file = File.join(@tempdir, 'testhosts')
    File.write(hosts_file, <<~HOSTS)
      192.168.1.1 server server.local srv
    HOSTS

    ENV['HOSTFILE'] = hosts_file

    results = complete_hostname('s')
    assert_includes results, 'server'
    assert_includes results, 'server.local'
    assert_includes results, 'srv'
  end

  def test_complete_hostname_sorted
    hosts_file = File.join(@tempdir, 'testhosts')
    File.write(hosts_file, <<~HOSTS)
      10.0.0.1 xyzsorttest-zebra
      10.0.0.2 xyzsorttest-alpha
      10.0.0.3 xyzsorttest-middle
    HOSTS

    ENV['HOSTFILE'] = hosts_file

    results = complete_hostname('xyzsorttest')
    assert_equal ['xyzsorttest-alpha', 'xyzsorttest-middle', 'xyzsorttest-zebra'], results
  end

  def test_complete_hostname_unique
    hosts_file = File.join(@tempdir, 'testhosts')
    File.write(hosts_file, <<~HOSTS)
      10.0.0.1 xyzuniquehost
      10.0.0.2 xyzuniquehost
      10.0.0.3 xyzuniquehost
    HOSTS

    ENV['HOSTFILE'] = hosts_file

    results = complete_hostname('xyzunique')
    assert_equal ['xyzuniquehost'], results
  end

  def test_complete_hostname_nonexistent_hostfile
    ENV['HOSTFILE'] = '/nonexistent/path/to/hosts'

    # Should not raise, just return empty or results from /etc/hosts
    results = complete_hostname('xyz_unlikely_prefix')
    # Just verify it doesn't crash
    assert results.is_a?(Array)
  end

  def test_complete_hostname_reads_etc_hosts
    # This test verifies /etc/hosts is read (localhost should be there)
    results = complete_hostname('local')
    # localhost is typically in /etc/hosts
    assert_includes results, 'localhost'
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt hostcomplete')
    end
    assert_match(/hostcomplete/, output)
    assert_match(/on/, output)

    execute('shopt -u hostcomplete')

    output = capture_output do
      execute('shopt hostcomplete')
    end
    assert_match(/hostcomplete/, output)
    assert_match(/off/, output)
  end
end
