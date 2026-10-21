require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

class TestCurbTransferGuard < Test::Unit::TestCase
  class InterruptedTransfer < StandardError; end

  [:perform, :_socket_perform].each do |drive|
    define_method("test_#{drive}_rejects_cross_thread_handle_access") do
      with_waiting_transfer(drive) do |easy, multi, worker, release|
        operations = {
          close: -> { easy.close },
          reset: -> { easy.reset },
          initialize: -> { easy.__send__(:initialize) },
          clone: -> { easy.clone },
          dup: -> { easy.dup },
          setopt: -> { easy.setopt(Curl::CURLOPT_CUSTOMREQUEST, 'DELETE') },
          post_body: -> { easy.post_body = 'replacement' },
          url: -> { easy.url = 'http://127.0.0.1/' },
          timeout: -> { easy.timeout = 1 },
          multi_assignment: -> { easy.multi = nil },
          multi_remove: -> { multi.remove(easy) },
          multi_close: -> { multi.close },
          multi_initialize: -> { multi.__send__(:initialize) },
          multi_add: -> { multi.add(Curl::Easy.new('http://127.0.0.1/')) },
          multi_option: -> { multi.max_connects = 1 }
        }
        operations.each do |name, operation|
          error = assert_raise(RuntimeError, name.to_s, &operation)
          assert_match(/another thread|active Curl::Multi/, error.message, name.to_s)
        end
        assert_equal [easy], multi.requests.values

        release << true
        assert worker.join(5), 'perform did not finish'
        worker.value
        assert_equal 'ok', easy.body_str
        assert_nothing_raised { easy.clone.close }
        assert_nothing_raised { easy.reset }
        assert_nothing_raised { easy.close }
      end
    end

    define_method("test_#{drive}_releases_guard_after_interruption") do
      with_waiting_transfer(drive) do |easy, multi, worker, release|
        worker.raise(InterruptedTransfer, 'stop')
        assert worker.join(5), 'interrupted perform did not finish'
        assert_kind_of InterruptedTransfer, worker[:transfer_error]
        assert_nothing_raised { multi.remove(easy) }
        assert_nothing_raised { easy.reset }
        assert_nothing_raised { easy.close }
        release << true
      end
    end
  end

  def with_waiting_transfer(drive)
    if drive == :_socket_perform && !Curl::Multi.private_method_defined?(drive)
      omit('socket-action perform path is not available')
    end
    server = TCPServer.new('127.0.0.1', 0)
    started = Queue.new
    release = Queue.new
    server_thread = Thread.new do
      socket = server.accept
      begin
        request = +''
        request << socket.readpartial(4096) until request.include?("\r\n\r\n")
        started << true
        release.pop
        socket.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
      rescue Errno::EPIPE, Errno::ECONNRESET
        # The interruption test intentionally closes the connection early.
      ensure
        socket.close
      end
    end
    easy = Curl::Easy.new("http://127.0.0.1:#{server.addr[1]}/")
    multi = Curl::Multi.new
    # Exercise reuse after autoclose as well as the active-transfer checks.
    previous_autoclose = Curl::Multi.autoclose
    begin
      Curl::Multi.autoclose = true
      multi.add(Curl::Easy.new($TEST_URL))
      multi.perform
    ensure
      Curl::Multi.autoclose = previous_autoclose
    end
    multi.add(easy)
    worker = Thread.new do
      Thread.current.report_on_exception = false if Thread.current.respond_to?(:report_on_exception=)
      begin
        multi.__send__(drive)
      rescue InterruptedTransfer => error
        # Keep join non-raising so the test can inspect the exception explicitly.
        Thread.current[:transfer_error] = error
      end
    end
    Timeout.timeout(5) { started.pop }
    yield easy, multi, worker, release
  ensure
    release << true if release
    if worker && worker.alive?
      worker.kill
      worker.join(5)
    end
    multi.close if multi
    server.close if server && !server.closed?
    if server_thread
      server_thread.join(5)
      server_thread.kill if server_thread.alive?
    end
  end
end
