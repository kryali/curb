require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

class TestCurbCurlErrorMappings < Test::Unit::TestCase
  def assert_easy_error_mapping(code, expected_class)
    actual_class, message = Curl::Easy.error(code)

    assert_equal expected_class, actual_class
    assert_kind_of String, message
    assert_not_empty message
  end

  def test_easy_error_known_mappings
    assert_easy_error_mapping(0, Curl::Err::CurlOK)
    assert_easy_error_mapping(1, Curl::Err::UnsupportedProtocolError)
    assert_easy_error_mapping(2, Curl::Err::FailedInitError)
    assert_easy_error_mapping(3, Curl::Err::MalformedURLError)
    assert_easy_error_mapping(5, Curl::Err::ProxyResolutionError)
    assert_easy_error_mapping(6, Curl::Err::HostResolutionError)
    assert_easy_error_mapping(7, Curl::Err::ConnectionFailedError)
    assert_easy_error_mapping(23, Curl::Err::WriteError)
    assert_easy_error_mapping(26, Curl::Err::ReadError)
    assert_easy_error_mapping(28, Curl::Err::TimeoutError)
    assert_easy_error_mapping(42, Curl::Err::AbortedByCallbackError)
    assert_easy_error_mapping(47, Curl::Err::TooManyRedirectsError)
    assert_easy_error_mapping(52, Curl::Err::GotNothingError)
    assert_easy_error_mapping(55, Curl::Err::SendError)
    assert_easy_error_mapping(56, Curl::Err::RecvError)
    assert_easy_error_mapping(57, Curl::Err::ShareInUseError)
    assert_easy_error_mapping(58, Curl::Err::SSLCertificateError)
    assert_easy_error_mapping(59, Curl::Err::SSLCypherError)
    assert_easy_error_mapping(61, Curl::Err::BadContentEncodingError)
    assert_easy_error_mapping(63, Curl::Err::FileSizeExceededError)
    assert_easy_error_mapping(64, Curl::Err::FTPSSLFailed)

    ssl_peer_or_ca_error =
      if Gem::Version.new(Curl::CURL_VERSION) >= Gem::Version.new('7.62.0')
        Curl::Err::SSLPeerCertificateError
      else
        Curl::Err::SSLCACertificateError
      end

    assert_easy_error_mapping(60, ssl_peer_or_ca_error)
  end

  def test_easy_error_returns_error_info_for_known_numeric_range
    0.upto(92) do |code|
      error_class, message = Curl::Easy.error(code)

      assert_kind_of Class, error_class
      assert error_class <= Curl::Err::CurlError
      assert_kind_of String, message
      assert_not_empty message
    end
  end

  def test_easy_error_uses_generic_mapping_for_unknown_codes
    error_class, message = Curl::Easy.error(9_999)

    assert_equal Curl::Err::CurlError, error_class
    assert_equal 'Unknown error result from libcurl', message
  end
end

class TestCurbCurlNativeCoverage < Test::Unit::TestCase
  include TestServerMethods

  def setup
    server_setup
  end

  def test_clone_preserves_native_lists_after_original_handle_closes
    easy = Curl::Easy.new("http://curb.invalid:#{TestServlet.port}#{TestServlet.path}")
    easy.proxy_url = ""
    easy.headers['X-Test'] = '1'
    easy.proxy_headers['X-Proxy'] = '2'
    easy.ftp_commands = ['PWD']
    easy.resolve = ["curb.invalid:#{TestServlet.port}:127.0.0.1"]

    clone = easy.clone
    easy.close

    clone.http_get

    assert_equal 'GET', clone.body_str
    assert_equal '1', clone.headers['X-Test']
    assert_equal '2', clone.proxy_headers['X-Proxy']
    assert_equal ['PWD'], clone.ftp_commands
    assert_equal ["curb.invalid:#{TestServlet.port}:127.0.0.1"], clone.resolve
  ensure
    clone.close if defined?(clone) && clone
    easy.close if defined?(easy) && easy
  end

  def test_clone_rebinds_upload_callbacks_to_clone_state
    easy = Curl::Easy.new(TestServlet.url)
    easy.put_data = 'clone-data'

    clone = easy.clone
    easy.put_data = 'other-data'

    clone.perform

    assert_equal "PUT\nclone-data", clone.body_str
  ensure
    clone.close if defined?(clone) && clone
    easy.close if defined?(easy) && easy
  end

  [:clone, :dup].each do |copy_method|
    [:on_body, :on_header, :on_progress, :on_debug, :on_complete].each do |callback|
      define_method("test_#{copy_method}_during_multipart_#{callback}_detaches_form") do
        easy = Curl::Easy.new(TestServlet.url)
        easy.multipart_form_post = true
        easy.verbose = true if callback == :on_debug
        copies = []
        easy.public_send(callback) do |*args|
          if copies.empty?
            # The public option can change while the native form is attached.
            easy.multipart_form_post = false
            copies << easy.public_send(copy_method)
          end
          [:on_body, :on_header].include?(callback) ? args.first.bytesize : true
        end

        easy.http_post(Curl::PostField.content('original', 'temporary-form'))
        assert_equal 1, copies.size, "#{callback} must run during the multipart request"
        copy = copies.first
        copy.public_send(callback) # Remove the inherited callback.
        copy.verbose = false

        # Plain perform must not access or resend the original's freed form.
        copy.perform
        easy.public_send(callback)
        easy.verbose = false
        easy.perform
        assert_equal easy.body_str, copy.body_str
        assert_no_match(/temporary-form|name="original"/, copy.body_str)

        copy.multipart_form_post = true
        copy.http_post(Curl::PostField.content('replacement', 'fresh-form'))
        assert_match(/name="replacement"/, copy.body_str)
        assert_match(/fresh-form/, copy.body_str)
        assert_no_match(/temporary-form/, copy.body_str)
      ensure
        copies&.each(&:close)
        easy&.close
      end
    end

    define_method("test_#{copy_method}_preserves_post_after_multipart_cleanup") do
      easy = Curl::Easy.new(TestServlet.url)
      easy.multipart_form_post = true
      easy.http_post(Curl::PostField.content('original', 'temporary-form'))
      easy.multipart_form_post = false
      easy.post_body = 'ordinary=post'

      copy = easy.public_send(copy_method)
      copy.perform
      assert_equal "POST\nordinary=post", copy.body_str
    ensure
      copy&.close
      easy&.close
    end
  end

  def test_native_accessors_round_trip
    easy = Curl::Easy.new(TestServlet.url)

    assert_equal '127.0.0.1', easy.interface = '127.0.0.1'
    assert_equal 'user:pass', easy.userpwd = 'user:pass'
    assert_equal 'proxy:pass', easy.proxypwd = 'proxy:pass'
    assert_equal 'tests/cert.pem', easy.cert_key = 'tests/cert.pem'
    assert_equal 'gzip', easy.encoding = 'gzip'

    if easy.respond_to?(:max_send_speed_large=)
      assert_equal 123, easy.max_send_speed_large = 123
      assert_equal 123, easy.max_send_speed_large
    end

    if easy.respond_to?(:max_recv_speed_large=)
      assert_equal 456, easy.max_recv_speed_large = 456
      assert_equal 456, easy.max_recv_speed_large
    end

    assert_equal '127.0.0.1', easy.interface
    assert_equal 'user:pass', easy.userpwd
    assert_equal 'proxy:pass', easy.proxypwd
    assert_equal 'tests/cert.pem', easy.cert_key
    assert_equal 'gzip', easy.encoding
  ensure
    easy.close if defined?(easy) && easy
  end

  def test_upload_round_trips_stream_and_offset
    upload = Curl::Upload.new
    stream = StringIO.new('payload')

    assert_same stream, upload.stream = stream
    assert_same stream, upload.stream
    assert_equal 7, upload.offset = 7
    assert_equal 7, upload.offset
  end
end
