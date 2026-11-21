# frozen_string_literal: true

require_relative 'test_helper'

# TIMEFORMAT controls what `time` prints: %R real, %U user, %S system
# seconds, with an optional precision digit, and %P the CPU percentage
class TestTimeformat < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('unset TIMEFORMAT')
  end

  def time_output(script)
    capture_stderr { execute(script) }
  end

  def test_default_format_prints_real_user_sys
    out = time_output('time true')
    assert_match(/\A\nreal\t0m[0-9.]+s\nuser\t0m[0-9.]+s\nsys\t0m[0-9.]+s\n\z/, out)
  end

  def test_timeformat_real_seconds_only
    execute('TIMEFORMAT=%R')
    assert_match(/\A[0-9]+\.[0-9]{3}\n\z/, time_output('time true'))
  end

  def test_timeformat_precision_and_literal_text
    execute("TIMEFORMAT='took %1R s, cpu %P%%'")
    assert_match(/\Atook [0-9]+\.[0-9] s, cpu [0-9.]+%\n\z/, time_output('time true'))
  end

  def test_empty_timeformat_prints_nothing
    execute('TIMEFORMAT=')
    assert_equal '', time_output('time true')
  end
end
