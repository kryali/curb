require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

class TestCurbCurlMaxFileSize < Test::Unit::TestCase
  def setup
    @easy = Curl::Easy.new
  end

  def teardown
    Curl.__send__(:clear_safe!) if Curl.respond_to?(:clear_safe!, true)
    super
  end

  def test_safe_body_limit_defaults_and_raw_requests
    assert_equal 10 * 1024 * 1024, Curl::SafetyConfig.new.max_body_bytes
    assert_nil @easy.max_body_bytes
    stub_public_network_policy_for_local_fixture(@easy)
    @easy.safe_http!
    assert_equal Curl::SafetyConfig::DEFAULT_MAX_BODY_BYTES, @easy.max_body_bytes
    @easy.max_body_bytes = nil
    Curl.__send__(:apply_safety!, @easy)
    assert_equal Curl::SafetyConfig::DEFAULT_MAX_BODY_BYTES, @easy.max_body_bytes
  end

  [:global, :helper, :handle].each do |mode|
    define_method("test_#{mode}_default_body_limit_rejects_oversized_response") do
      payload = 'x' * (Curl::SafetyConfig::DEFAULT_MAX_BODY_BYTES + 1)
      with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: #{payload.bytesize}\r\n\r\n#{payload}") do |url|
        assert_body_limit_error do
          if mode == :helper
            Curl.safe_get(url) { |easy| stub_public_network_policy_for_local_fixture(easy) }
          else
            Curl.safe! if mode == :global
            @easy.url = url
            stub_public_network_policy_for_local_fixture(@easy)
            @easy.safe_http! if mode == :handle
            @easy.perform
          end
        end
      end
    end
  end

  def test_default_body_limit_bounds_callback_delivery_without_content_length
    limit = Curl::SafetyConfig::DEFAULT_MAX_BODY_BYTES
    payload = 'x' * (limit + 1)
    received = 0
    with_raw_http_response("HTTP/1.0 200 OK\r\n\r\n#{payload}") do |url|
      @easy.url = url
      stub_public_network_policy_for_local_fixture(@easy)
      @easy.safe_http!
      @easy.on_body { |data| received += data.bytesize; data.bytesize }
      assert_body_limit_error { @easy.perform }
    end
    assert_operator received, :<=, limit
    assert_operator received, :>, 0
  end

  def test_global_body_limit_can_be_explicitly_disabled
    Curl.safe! { |config| config.max_body_bytes = nil }
    stub_public_network_policy_for_local_fixture(@easy)
    @easy.safe_http!
    assert_nil @easy.max_body_bytes
  end

  def test_safe_helper_accepts_explicit_larger_limit_and_unlimited
    [20 * 1024 * 1024, nil, 0].each do |limit|
      with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok") do |url|
        easy = Curl.safe_get(url, :max_body_bytes => limit) do |handle|
          stub_public_network_policy_for_local_fixture(handle)
        end
        assert_equal(limit == 0 ? nil : limit, easy.max_body_bytes)
        assert_equal 'ok', easy.body_str
      end
    end
  end

  def test_safe_helper_inherits_global_body_limit
    Curl.safe! { |config| config.max_body_bytes = 20 * 1024 * 1024 }
    stub_public_network_policy_for_local_fixture(@easy)
    @easy.safe_http!
    assert_equal 20 * 1024 * 1024, @easy.max_body_bytes
  end

  def test_safe_helper_cannot_weaken_global_body_limit
    Curl.safe! { |config| config.max_body_bytes = 10 }
    [100, nil, 0].each do |limit|
      with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 64\r\n\r\n#{'x' * 64}") do |url|
        assert_body_limit_error do
          Curl.safe_get(url, :max_body_bytes => limit) do |handle|
            stub_public_network_policy_for_local_fixture(handle)
          end
        end
      end
    end
  end

  def test_safe_http_rejects_negative_body_limit
    assert_raise(ArgumentError) { @easy.safe_http!(:max_body_bytes => -1) }
  end

  def test_maxfilesize_setopt
    @easy.set(Curl::CURLOPT_MAXFILESIZE, 5000000)
    @easy.set(Curl::CURLOPT_MAXFILESIZE_LARGE, 5000000) if Curl.const_defined?(:CURLOPT_MAXFILESIZE_LARGE)
  end

  def test_max_body_bytes_exact_limit_succeeds
    with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\n12345678") do |url|
      @easy.url = url
      @easy.max_body_bytes = 8
      @easy.perform

      assert_equal '12345678', @easy.body_str
    end
  end

  def test_max_body_bytes_rejects_large_buffered_response
    with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 64\r\n\r\n#{'x' * 64}") do |url|
      @easy.url = url
      @easy.max_body_bytes = 10

      assert_body_limit_error do
        @easy.perform
      end

      assert_operator @easy.body_str.to_s.bytesize, :<=, 10
    end
  end

  def test_safe_get_accepts_max_body_bytes_as_second_argument
    with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 64\r\n\r\n#{'x' * 64}") do |url|
      assert_body_limit_error do
        Curl.safe_get(url, :max_body_bytes => 10) { |easy| stub_public_network_policy_for_local_fixture(easy) }
      end
    end
  end

  def test_safe_get_reapplies_max_body_bytes_after_user_block
    with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 64\r\n\r\n#{'x' * 64}") do |url|
      assert_body_limit_error do
        Curl.safe_get(url, {}, :max_body_bytes => 10) do |easy|
          stub_public_network_policy_for_local_fixture(easy)
          easy.max_body_bytes = nil
        end
      end
    end
  end

  def test_safe_bang_max_body_bytes_applies_to_easy_perform
    with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 64\r\n\r\n#{'x' * 64}") do |url|
      Curl.safe! do |config|
        config.max_body_bytes = 10
      end

      @easy.url = url
      stub_public_network_policy_for_local_fixture(@easy)

      assert_body_limit_error do
        @easy.perform
      end
    end
  end

  def test_safe_bang_reapplies_max_body_bytes_after_shortcut_block
    with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 64\r\n\r\n#{'x' * 64}") do |url|
      Curl.safe! do |config|
        config.max_body_bytes = 10
      end

      assert_body_limit_error do
        Curl.get(url) do |easy|
          stub_public_network_policy_for_local_fixture(easy)
          easy.max_body_bytes = nil
        end
      end
    end
  end

  def test_safe_get_max_body_bytes_tightens_global_cap
    with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 64\r\n\r\n#{'x' * 64}") do |url|
      Curl.safe! do |config|
        config.max_body_bytes = 1_000
      end

      assert_body_limit_error do
        Curl.safe_get(url, :max_body_bytes => 10) { |easy| stub_public_network_policy_for_local_fixture(easy) }
      end
    end
  end

  def test_safe_bang_rejects_negative_max_body_bytes
    assert_raise(ArgumentError) do
      Curl.safe! do |config|
        config.max_body_bytes = -1
      end
    end
  end

  def test_safe_head_does_not_apply_body_cap_to_content_length
    with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 65536\r\n\r\n") do |url|
      easy = Curl.safe_head(url, :max_body_bytes => 1) { |handle| stub_public_network_policy_for_local_fixture(handle) }

      assert_equal 200, easy.response_code
      assert_equal '', easy.body_str
    end
  end

  def test_max_body_bytes_rejects_chunked_response_without_content_length
    chunks = ["1234", "5678", "90"]
    response = +"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
    chunks.each { |chunk| response << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n" }
    response << "0\r\n\r\n"

    with_raw_http_response(response) do |url|
      @easy.url = url
      @easy.max_body_bytes = 8

      assert_body_limit_error do
        @easy.perform
      end

      assert_operator @easy.body_str.to_s.bytesize, :<=, 8
    end
  end

  def test_max_body_bytes_limits_on_body_callback
    chunks = ["1234", "5678", "90"]
    response = +"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
    chunks.each { |chunk| response << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n" }
    response << "0\r\n\r\n"
    seen = +''

    with_raw_http_response(response) do |url|
      @easy.url = url
      @easy.max_body_bytes = 8
      @easy.on_body { |data| seen << data; data.bytesize }

      assert_body_limit_error do
        @easy.perform
      end

      assert_equal '12345678', seen
      assert_nil @easy.body_str
    end
  end

  def test_max_body_bytes_zero_clears_limit
    with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\n123456789012") do |url|
      @easy.url = url
      @easy.max_body_bytes = 1
      @easy.max_body_bytes = 0
      @easy.perform

      assert_nil @easy.max_body_bytes
      assert_equal '123456789012', @easy.body_str
    end
  end

  def test_max_body_bytes_counter_resets_between_reused_transfers
    @easy.max_body_bytes = 8

    with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\n12345678") do |url|
      @easy.url = url
      @easy.perform
      assert_equal '12345678', @easy.body_str
    end

    with_raw_http_response("HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nabcdefgh") do |url|
      @easy.url = url
      @easy.perform
      assert_equal 'abcdefgh', @easy.body_str
    end
  end

  private

  # Keep body-limit integration tests local; real destination enforcement is
  # covered separately in tc_curl_network_policy.rb.
  def stub_public_network_policy_for_local_fixture(easy)
    def easy.network_policy=(policy)
      raise "unexpected policy: #{policy}" unless policy == :public
    end
  end

  def assert_body_limit_error
    assert_raise(Curl::Err::FileSizeExceededError) do
      yield
    end
  end

  def with_raw_http_response(response)
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    thread = Thread.new do
      socket = server.accept
      begin
        socket.readpartial(4096)
      rescue EOFError
      end
      begin
        socket.write(response)
      rescue Errno::EPIPE, Errno::ECONNRESET
        # Expected when the client aborts at the body limit.
      ensure
        socket.close
      end
    end

    yield "http://127.0.0.1:#{port}/"
  ensure
    server.close if server && !server.closed?
    if thread
      thread.join(5)
      thread.kill if thread.alive?
    end
  end
end
