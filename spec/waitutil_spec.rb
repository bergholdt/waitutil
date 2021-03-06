require 'waitutil'
require 'socket'

RSpec.configure do |configuration|
  configuration.include WaitUtil
end

describe WaitUtil do
  describe '.wait_for_condition' do
    it 'logs if the verbose option is specified' do
      iterations = []
      WaitUtil.logger.should_receive(:info).with('Waiting for true for up to 60 seconds')
      WaitUtil.logger.should_receive(:info) do |msg|
        msg =~ /^Success waiting for true \(.*\)$/
      end

      ret = wait_for_condition('true', :verbose => true) do |iteration|
        iterations << iteration
        true
      end
      expect(ret).to be_true
      expect(iterations).to eq([0])
    end

    it 'returns immediately if the condition is true' do
      iterations = []
      ret = wait_for_condition('true') {|iteration| iterations << iteration; true }
      expect(ret).to be_true
      expect(iterations).to eq([0])
    end

    it 'should time out if the condition is always false' do
      iterations = []
      start_time = Time.now
      begin
        wait_for_condition('false', :timeout_sec => 0.1, :delay_sec => 0.01) do |iteration|
          iterations << iteration
          false
        end
        fail 'Expected an exception'
      rescue WaitUtil::TimeoutError => ex
        expect(ex.to_s).to match(/^Timed out waiting for false /)
      end
      elapsed_sec = Time.now - start_time
      expect(elapsed_sec).to be >= 0.1
      expect(iterations.length).to be >= 9
      expect(iterations.length).to be <= 11
      expect(iterations).to eq((0..iterations.length - 1).to_a)
    end

    it 'should handle additional messages from the block' do
      begin
        wait_for_condition('false', :timeout_sec => 0.01, :delay_sec => 0.05) do |iteration|
          [false, 'Some error']
        end
        fail 'Expected an exception'
      rescue WaitUtil::TimeoutError => ex
        expect(ex.to_s).to match(/^Timed out waiting for false (.*): Some error$/)
      end
    end

    it 'should treat the first element of returned tuple as condition status' do
      iterations = []
      ret = wait_for_condition('some condition', :timeout_sec => 1, :delay_sec => 0) do |iteration|
        iterations << iteration
        [iteration >= 3, 'some message']
      end
      expect(ret).to be_true
      expect(iterations).to eq([0, 1, 2, 3])
    end

    it 'should evaluate the block return value as a boolean if it is not an array' do
      iterations = []
      ret = wait_for_condition('some condition', :timeout_sec => 1, :delay_sec => 0) do |iteration|
        iterations << iteration
        iteration >= 3
      end
      expect(ret).to be_true
      expect(iterations).to eq([0, 1, 2, 3])
    end
  end

  describe '.wait_for_service' do
    BIND_IP = '127.0.0.1'

    it 'waits for service availability' do
      WaitUtil.wait_for_service('Google', 'google.com', 80, :timeout_sec => 0.5)
    end

    it 'times out when host name does not exist' do
      begin
        WaitUtil.wait_for_service(
          'non-existent service',
          'nosuchhost_waitutil_ruby_module.com',
          12345,
          :timeout_sec => 0.2,
          :delay_sec => 0.1
        )
        fail("Expecting WaitUtil::TimeoutError but nothing was raised")
      rescue WaitUtil::TimeoutError => ex
        expect(ex.to_s.gsub(/ \(.*/, '')).to eq(
          'Timed out waiting for non-existent service to become available on ' \
          'nosuchhost_waitutil_ruby_module.com, port 12345'
        )
      end
    end

    if RUBY_PLATFORM != 'java'
      # Our current implementation will get stuck on this if running JRuby.
      it 'times out when port is closed' do
        begin
          WaitUtil.wait_for_service(
            'wrong port on Google',
            'google.com',
            12345,
            :timeout_sec => 0.2,
            :delay_sec => 0.1
          )
        rescue WaitUtil::TimeoutError => ex
          expect(ex.to_s.gsub(/ \(.*/, '')).to eq(
            'Timed out waiting for wrong port on Google to become available on google.com, ' \
            'port 12345'
          )
        end
      end
    end

    it 'should succeed immediately when there is a TCP server listening' do
      # Find an unused port.
      socket = Socket.new(:INET, :STREAM, 0)
      sockaddr = if RUBY_ENGINE == 'jruby'
        ServerSocket.pack_sockaddr_in(0, "127.0.0.1")
      else
        Socket.pack_sockaddr_in(0, "127.0.0.1")
      end
      socket.bind(sockaddr)
      port = socket.local_address.ip_port
      socket.close

      server_thread = Thread.new do
        server = TCPServer.new(port)
        loop do
          client = server.accept  # Wait for a client to connect
          client.puts "Hello !"
          client.close
          break
        end
      end

      wait_for_service('wait for my service', BIND_IP, port, :delay_sec => 0.1, :timeout_sec => 0.3)
    end

    it 'should fail when there is no TCP server listening' do
      port = nil
      # Find a port that no one is listening on.
      attempts = 0
      while attempts < 100
        port = 32768 + rand(61000 - 32768)
        begin
          TCPSocket.new(BIND_IP, port)
          port = nil
        rescue Errno::ECONNREFUSED
          break
        end
        attempts += 1
      end
      fail 'Could not find a port no one is listening on' unless port

      expect {
        wait_for_service(
          'wait for non-existent service', BIND_IP, port, :delay_sec => 0.1, :timeout_sec => 0.3
        )
      }.to raise_error(WaitUtil::TimeoutError)
    end
  end

end
