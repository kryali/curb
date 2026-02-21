require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

class TestCurbShare < Test::Unit::TestCase
  include BugTestServerSetupTeardown

  def setup
    @port = 9994
    @response_proc = lambda do |res|
      res['Content-Type'] = 'text/plain'
      res.body = 'ok'
    end
    super
  end

  def test_share_close_idempotent
    share = Curl::Share.new
    assert_nothing_raised { share.close }
    assert_nothing_raised { share.close }
  end

  def test_enable_all_types
    share = Curl::Share.new
    assert_nothing_raised do
      share.enable :connections
      share.enable :dns
      share.enable :ssl_session
      share.enable :cookies
    end
  end

  def test_enable_unknown_symbol_raises
    share = Curl::Share.new
    assert_raise(ArgumentError) { share.enable :bogus }
  end

  def test_enable_on_closed_share_raises
    share = Curl::Share.new
    share.close
    assert_raise(RuntimeError) { share.enable :dns }
  end

  def test_easy_perform_with_share
    share = Curl::Share.new
    share.enable :dns
    easy = Curl::Easy.new("http://127.0.0.1:#{@port}/test")
    easy.share = share
    easy.perform
    assert_equal 200, easy.response_code
  end

  def test_concurrent_threads_no_crash
    share = Curl::Share.new
    share.enable :dns

    codes = []
    mutex = Mutex.new
    threads = 5.times.map do
      Thread.new do
        3.times do
          e = Curl::Easy.new("http://127.0.0.1:#{@port}/test")
          e.share = share
          e.perform
          mutex.synchronize { codes << e.response_code }
        end
      end
    end
    threads.each(&:join)

    assert_equal [200] * 15, codes
  end

  def test_multi_with_share
    share = Curl::Share.new
    share.enable :dns

    multi   = Curl::Multi.new
    handles = 3.times.map do
      e = Curl::Easy.new("http://127.0.0.1:#{@port}/test")
      e.share = share
      e
    end
    handles.each { |e| multi.add(e) }
    multi.perform

    assert_equal [200] * 3, handles.map(&:response_code)
  end
end
