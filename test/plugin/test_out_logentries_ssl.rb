require "helper"
require "fluent/plugin/out_logentries_ssl.rb"


class LogentriesSSLOutTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
  end

  def setup
    Dir.mkdir('test/tmp')
  end

  def teardown
    Dir.glob('test/tmp/*').each {|f| File.unlink(f) }
    Dir.rmdir('test/tmp')
  end

  CONF = %[
          max_retries 2
          verify_fqdn false
          token token
          ]

  def stub_socket
    socket = mock('tcpsocket')
    socket.stubs(:connect).returns(socket)
    socket.stubs(:sync_close=)
    socket.stubs(:close)
    OpenSSL::SSL::SSLSocket.expects(:new).at_least_once.with(any_parameters).returns(socket)
    return socket
  end


  test "configuration" do
    d = create_driver(CONF)
    assert_equal 2, d.instance.max_retries
    assert_equal 443, d.instance.le_port
    assert_equal 'data.logentries.com', d.instance.le_host
  end

  test "sending to logentries" do
    socket = stub_socket
    message = {"message" => "Hello"}
    socket.expects(:write).with(regexp_matches(/^token {.*message.*Hello.*}\s+/i))
    d = create_driver(CONF)
    time = event_time('2017-01-01 13:37:00 UTC')
    d.run(default_tag: 'app') do
      d.feed(time, message)
    end
  end

  test "retries on errors" do
    socket = stub_socket
    message = {"message" => "Hello"}
    socket.expects(:write).with(anything).twice.raises(Errno::ECONNRESET).then.returns("ok")
    d = create_driver(CONF)
    time = event_time('2017-01-01 13:37:00 UTC')
    d.run(default_tag: 'app') do
      d.feed(time, message)
    end
  end

  test "sending too large events to LE" do
    socket = stub_socket
    message = {"hello" =>
               "a"*(Fluent::Plugin::LogentriesSSL::MessageHelper::MAX_SIZE + 100)}
    socket.expects(:write).with(anything).twice
    d = create_driver(CONF)
    time = event_time('2017-01-01 13:37:00 UTC')
    d.run(default_tag: 'app') do
      d.feed(time, message)
    end
  end

  private

  def create_driver(conf)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::LogentriesSSL::Output).configure(conf)
  end
end
