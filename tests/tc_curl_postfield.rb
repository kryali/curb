require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

class TestCurbCurlPostfield < Test::Unit::TestCase
  def test_private_new
    assert_raise(NoMethodError) { Curl::PostField.new }
  end

  def test_new_content_01
    pf = Curl::PostField.content('foo', 'bar')

    assert_equal 'foo', pf.name
    assert_equal 'bar', pf.content
    assert_nil pf.content_type
    assert_nil pf.local_file
    assert_nil pf.remote_file
    assert_nil pf.set_content_proc
  end

  def test_new_content_02
    pf = Curl::PostField.content('foo', 'bar', 'text/html')

    assert_equal 'foo', pf.name
    assert_equal 'bar', pf.content
    assert_equal 'text/html', pf.content_type
    assert_nil pf.local_file
    assert_nil pf.remote_file
    assert_nil pf.set_content_proc
  end

  def test_new_content_03
    l = lambda { |field| "never gets run" }
    pf = Curl::PostField.content('foo', &l)

    assert_equal 'foo', pf.name
    assert_nil pf.content
    assert_nil pf.content_type
    assert_nil pf.local_file
    assert_nil pf.remote_file

    # N.B. This doesn't just get the proc, but also removes it.
    assert_equal l, pf.set_content_proc
  end

  def test_new_content_04
    l = lambda { |field| "never gets run" }
    pf = Curl::PostField.content('foo', 'text/html', &l)

    assert_equal 'foo', pf.name
    assert_nil pf.content
    assert_equal 'text/html', pf.content_type
    assert_nil pf.local_file
    assert_nil pf.remote_file

    # N.B. This doesn't just get the proc, but also removes it.
    assert_equal l, pf.set_content_proc
  end


  def test_new_file_01
    pf = Curl::PostField.file('foo', 'localname')
    pf.content_type = 'text/super'

    assert_equal 'foo', pf.name
    assert_equal 'localname', pf.local_file
    assert_equal 'localname', pf.remote_file
    assert_nothing_raised { pf.to_s }
    assert_equal 'text/super', pf.content_type
    assert_nil pf.content
    assert_nil pf.set_content_proc
  end

  def test_new_file_02
    pf = Curl::PostField.file('foo', 'localname', 'remotename')

    assert_equal 'foo', pf.name
    assert_equal 'localname', pf.local_file
    assert_equal 'remotename', pf.remote_file
    assert_nil pf.content_type
    assert_nil pf.content
    assert_nil pf.set_content_proc
  end

  def test_new_file_03
    l = lambda { |field| "never gets run" }
    pf = Curl::PostField.file('foo', 'remotename', &l)

    assert_equal 'foo', pf.name
    assert_equal 'remotename', pf.remote_file
    assert_nil pf.local_file
    assert_nil pf.content_type
    assert_nil pf.content

    # N.B. This doesn't just get the proc, but also removes it.
    assert_equal l, pf.set_content_proc
  end

  def test_new_file_04
    assert_raise(ArgumentError) do
      # no local name, no block
      Curl::PostField.file('foo')
    end

    assert_raise(ArgumentError) do
      # no remote name with block
      Curl::PostField.file('foo') { |field| "never runs" }
    end
  end

  def test_new_file_05
    # local gets ignored when supplying a block, but remote
    # is still set up properly.
    l = lambda { |field| "never runs" }
    pf = Curl::PostField.file('foo', 'local', 'remote', &l)

    assert_equal 'foo', pf.name
    assert_equal 'remote', pf.remote_file
    assert_nil pf.local_file
    assert_nil pf.content_type
    assert_nil pf.content

    assert_equal l, pf.set_content_proc
  end

  def test_to_s_01
    pf = Curl::PostField.content('foo', 'bar')
    assert_equal "foo=bar", pf.to_s
  end

  def test_to_s_02
    pf = Curl::PostField.content('foo', 'bar ton')
    assert_equal "foo=bar%20ton", pf.to_s
  end

  def test_to_s_03
    pf = Curl::PostField.content('foo') { |field| field.name.upcase + "BAR" }
    assert_equal "foo=FOOBAR", pf.to_s
  end

  def test_content_proc_survives_gc
    pf = postfield_with_only_native_proc_reference

    10.times do
      GC.start(full_mark: true, immediate_sweep: true)
      GC.compact if GC.respond_to?(:compact)
    end

    assert_equal "foo=FOOBAR", pf.to_s
  end

  def test_to_s_04
    pf = Curl::PostField.file('foo.file', 'bar.file')
    assert_nothing_raised { pf.to_s }
    #assert_raise(Curl::Err::InvalidPostFieldError) { pf.to_s }
  end

  def postfield_with_only_native_proc_reference
    Curl::PostField.content('foo') { |field| field.name.upcase + "BAR" }
  end
end

class TestCurbCurlPostfieldNativeCoverage < Test::Unit::TestCase
  def test_attribute_writers_round_trip
    pf = Curl::PostField.content('foo', 'bar')

    assert_equal 'renamed', pf.name = 'renamed'
    assert_equal 'payload', pf.content = 'payload'
    assert_equal 'text/plain', pf.content_type = 'text/plain'
    assert_equal 'local.txt', pf.local_file = 'local.txt'
    assert_equal 'remote.txt', pf.remote_file = 'remote.txt'

    assert_equal 'renamed', pf.name
    assert_equal 'payload', pf.content
    assert_equal 'text/plain', pf.content_type
    assert_equal 'local.txt', pf.local_file
    assert_equal 'remote.txt', pf.remote_file
  end

  def test_to_s_accepts_non_string_name_via_to_s
    name_like = Object.new
    def name_like.to_s
      'fancy name'
    end

    pf = Curl::PostField.content(name_like, 'value')
    assert_equal 'fancy%20name=value', pf.to_s
  end

  def test_to_s_uses_remote_file_when_local_file_is_missing
    pf = Curl::PostField.file('upload', 'local.txt', 'remote.txt')
    pf.local_file = nil

    assert_equal 'upload=remote.txt', pf.to_s
  end

  def test_to_s_rejects_name_without_to_s
    name_like = Class.new do
      undef to_s
    end.new

    pf = Curl::PostField.content(name_like, 'value')

    error = assert_raise(Curl::Err::InvalidPostFieldError) { pf.to_s }
    assert_match(/Cannot convert unnamed field to string/, error.message)
  end

  def test_to_s_rejects_content_without_to_s
    content_like = Class.new do
      undef to_s
    end.new

    pf = Curl::PostField.content('name', content_like)

    error = assert_raise(RuntimeError) { pf.to_s }
    assert_match(/does not respond_to to_s/, error.message)
  end

  def test_multipart_rejects_unnamed_field
    curl = Curl::Easy.new(TestServlet.url)
    curl.multipart_form_post = true
    pf = Curl::PostField.content('name', 'value')
    pf.name = nil

    error = assert_raise(Curl::Err::InvalidPostFieldError) { curl.http_post(pf) }
    assert_match(/Cannot post unnamed field/, error.message)
  end

  def test_multipart_rejects_content_field_without_data
    curl = Curl::Easy.new(TestServlet.url)
    curl.multipart_form_post = true
    pf = Curl::PostField.content('name', 'value')
    pf.content = nil

    error = assert_raise(Curl::Err::InvalidPostFieldError) { curl.http_post(pf) }
    assert_match(/Cannot post content field with no data/, error.message)
  end

  def test_multipart_rejects_file_field_without_filename
    curl = Curl::Easy.new(TestServlet.url)
    curl.multipart_form_post = true
    pf = Curl::PostField.file('upload', 'remote.txt') { 'payload' }
    pf.local_file = 'dummy.txt'
    pf.remote_file = nil

    error = assert_raise(Curl::Err::InvalidPostFieldError) { curl.http_post(pf) }
    assert_match(/Cannot post file upload field with no filename/, error.message)
  end
end

class TestCurbCurlPostfieldMultipartCoverage < Test::Unit::TestCase
  include TestServerMethods

  def setup
    server_setup
  end

  [:http_post, :http_patch, :http_put].each do |method|
    [:close, :reset, :initialize, :perform, :http_post, :post_body=].each do |operation|
      [:proc, :coercion].each do |source|
        define_method("test_#{method}_guards_#{operation}_from_#{source}") do
          curl = Curl::Easy.new(TestServlet.url)
          curl.multipart_form_post = true
          action = lambda do |*_|
            if operation == :post_body=
              curl.post_body = 'replacement'
            elsif operation == :http_post
              curl.http_post(Curl::PostField.content('nested', 'payload'))
            else
              curl.__send__(operation)
            end
            'payload'
          end
          field = if source == :proc
            Curl::PostField.content('trigger', &action)
          else
            value = Object.new
            value.define_singleton_method(:to_str, &action)
            Curl::PostField.content('trigger', value)
          end

          error = assert_raise(RuntimeError) do
            curl.__send__(method, Curl::PostField.content('first', 'allocated'), field)
          end
          assert_match(/active curl handle/, error.message)

          # Both partial forms and guards must unwind before reuse.
          curl.multipart_form_post = false
          curl.perform
          assert_equal 'GET', curl.body_str
          assert_nothing_raised { curl.reset }
          assert_nothing_raised { curl.close }
        end
      end
    end
  end

  [:content, :file].each do |kind|
    [false, true].each do |dynamic|
      define_method("test_multipart_snapshots_#{kind}_#{dynamic ? 'proc' : 'direct'}") do
        name = +'original_name'
        payload = +"original\0payload"
        field = multipart_field(kind, dynamic, nil, payload)
        field.name = name
        later = Curl::PostField.content('later') do
          Thread.new do
            name.replace('changed_name' * 1000)
            payload.replace('changed_payload' * 1000)
            field.content = nil
            field.name = nil
            GC.start
            GC.verify_compaction_references(double_heap: true, toward: :empty) if GC.respond_to?(:verify_compaction_references)
          end.join
          'later_value'
        end
        curl = Curl::Easy.new(TestServlet.url)
        curl.multipart_form_post = true
        curl.http_post(field, later)

        assert_include curl.body_str, 'name="original_name"'
        assert_include curl.body_str, "original\0payload"
        assert_include curl.body_str, 'filename="remote.txt"' if kind == :file
        assert_not_include curl.body_str, 'changed_payload'
      end
    end
  end

  def test_multipart_snapshots_before_later_coercions_in_same_field
    name = +'original_name'
    payload = +'original_payload'
    content_type = Object.new
    content_type.define_singleton_method(:to_str) do
      name.replace('changed_name' * 1000)
      payload.replace('changed_payload' * 1000)
      'text/plain'
    end
    field = Curl::PostField.content(name, payload, content_type)
    curl = Curl::Easy.new(TestServlet.url)
    curl.multipart_form_post = true
    curl.http_post(field)

    assert_include curl.body_str, 'name="original_name"'
    assert_include curl.body_str, 'original_payload'
  end

  # Exercise each pointer/length pair with and without a content type.
  [:content, :file].each do |kind|
    [false, true].each do |dynamic|
      [nil, 'text/plain'].each do |content_type|
        variant = "#{kind}_#{dynamic ? 'proc' : 'direct'}_#{content_type ? 'typed' : 'untyped'}"

        define_method("test_multipart_coerces_#{variant}") do
          payload = "before\0after"
          string_like = Object.new
          string_like.define_singleton_method(:to_str) { payload }
          field = multipart_field(kind, dynamic, content_type, string_like)
          curl = Curl::Easy.new(TestServlet.url)
          curl.multipart_form_post = true

          curl.http_post(field)

          assert_include curl.body_str, payload
          assert_equal payload, field.content unless dynamic
        end

        define_method("test_multipart_rejects_non_string_#{variant}") do
          field = multipart_field(kind, dynamic, content_type, 5)
          curl = Curl::Easy.new(TestServlet.url)
          curl.multipart_form_post = true

          assert_raise(TypeError) { curl.http_post(field) }
        end
      end
    end
  end

  def multipart_field(kind, dynamic, content_type, value)
    field = if dynamic
      if kind == :file
        Curl::PostField.file('upload', 'remote.txt') { value }
      else
        Curl::PostField.content('value') { value }
      end
    elsif kind == :file
      upload = Curl::PostField.file('upload', 'remote.txt')
      upload.content = value
      upload
    else
      Curl::PostField.content('value', value)
    end
    field.content_type = content_type
    field
  end

  def test_multipart_content_variants_include_dynamic_and_typed_fields
    curl = Curl::Easy.new(TestServlet.url)
    curl.multipart_form_post = true

    proc_without_type = Curl::PostField.content('proc_without_type') { 'alpha' }
    proc_with_type = Curl::PostField.content('proc_with_type', 'text/plain') { 'beta' }
    direct_with_type = Curl::PostField.content('direct_with_type', 'gamma', 'text/plain')

    curl.http_post([proc_without_type, proc_with_type, direct_with_type])
    body = curl.body_str

    assert_match(/name="proc_without_type"/, body)
    assert_match(/alpha/, body)
    assert_match(/name="proc_with_type"/, body)
    assert_match(/beta/, body)
    assert_match(/name="direct_with_type"/, body)
    assert_match(/gamma/, body)
    assert_match(/Content-Type: text\/plain/, body)
  end

  def test_multipart_file_variants_include_buffered_and_local_uploads
    readme = File.expand_path(File.join(File.dirname(__FILE__), '..', 'README.md'))

    proc_without_type = Curl::PostField.file('proc_without_type', 'proc_without_type.txt') { 'alpha' }
    proc_with_type = Curl::PostField.file('proc_with_type', 'proc_with_type.txt') { 'beta' }
    proc_with_type.content_type = 'text/plain'

    direct_without_type = Curl::PostField.file('direct_without_type', 'ignored.txt', 'direct_without_type.txt')
    direct_without_type.content = 'gamma'
    direct_without_type.local_file = nil

    direct_with_type = Curl::PostField.file('direct_with_type', 'ignored.txt', 'direct_with_type.txt')
    direct_with_type.content = 'delta'
    direct_with_type.local_file = nil
    direct_with_type.content_type = 'text/plain'

    local_with_type = Curl::PostField.file('local_with_type', readme)
    local_with_type.content_type = 'text/plain'

    curl = Curl::Easy.new(TestServlet.url)
    curl.multipart_form_post = true
    curl.http_post([proc_without_type, proc_with_type, direct_without_type, direct_with_type, local_with_type])
    body = curl.body_str

    assert_match(/name="proc_without_type"/, body)
    assert_match(/filename="proc_without_type.txt"/, body)
    assert_match(/alpha/, body)

    assert_match(/name="proc_with_type"/, body)
    assert_match(/filename="proc_with_type.txt"/, body)
    assert_match(/beta/, body)

    assert_match(/name="direct_without_type"/, body)
    assert_match(/filename="direct_without_type.txt"/, body)
    assert_match(/gamma/, body)

    assert_match(/name="direct_with_type"/, body)
    assert_match(/filename="direct_with_type.txt"/, body)
    assert_match(/delta/, body)

    assert_match(/name="local_with_type"/, body)
    assert_match(/Curb - Libcurl bindings for Ruby/, body)
    assert_match(/Content-Type: text\/plain/, body)
  end
end

class TestCurbCurlPostfieldInvalidToS < Test::Unit::TestCase
  class BadToS
    def to_s
      42
    end
  end

  def test_to_s_with_non_string_content_to_s_result_does_not_crash
    pf = Curl::PostField.content('name', BadToS.new)
    body = nil
    assert_nothing_raised { body = pf.to_s }
    assert_kind_of String, body
    assert body.start_with?('name=')
  end

  def test_to_s_with_non_string_name_to_s_result_does_not_crash
    pf = Curl::PostField.content(BadToS.new, 'value')
    body = nil
    assert_nothing_raised { body = pf.to_s }
    assert_kind_of String, body
  end

  def test_to_s_with_content_proc_returning_non_string_does_not_crash
    pf = Curl::PostField.content('name') { BadToS.new }
    assert_nothing_raised { pf.to_s }
  end

  def test_to_s_content_proc_raising_error_still_propagates
    pf = Curl::PostField.content('name') { raise 'boom' }
    error = assert_raise(RuntimeError) { pf.to_s }
    assert_equal 'boom', error.message
  end

  def test_to_s_still_coerces_objects_with_valid_to_s
    pf = Curl::PostField.content('name', 42)
    assert_equal 'name=42', pf.to_s
  end
end
