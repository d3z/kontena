require_relative '../../../spec_helper'

describe Kontena::Workers::ContainerHealthCheckWorker do

  let(:container) { spy(:container) }
  let(:queue) { Queue.new }
  let(:subject) { described_class.new(container, queue) }

  before(:each) { Celluloid.boot }
  after(:each) { Celluloid.shutdown }

  describe '#start' do
    it 'checks http status' do
      labels = {
        'io.kontena.health_check.protocol' => 'http',
        'io.kontena.health_check.uri' => '/',
        'io.kontena.health_check.port' => '8080',
        'io.kontena.health_check.timeout' => '10',
        'io.kontena.health_check.interval' => '30',
        'io.kontena.health_check.initial_delay' => '20',
      }
        
      allow(container).to receive(:labels).and_return(labels)
      allow(container).to receive(:overlay_cidr).and_return('1.2.3.4/16')
      expect(subject.wrapped_object).to receive(:every).with(30).and_yield
      expect(subject.wrapped_object).to receive(:sleep).with(20)
      expect(subject.wrapped_object).to receive(:check_http_status).with('1.2.3.4', 8080, '/', 10).twice.and_return({})
      expect {
        subject.start
      }.to change {queue.size}.by (2) # runs check after initial delay and once within the every block
    end

    it 'checks tcp status' do
      labels = {
        'io.kontena.health_check.protocol' => 'tcp',
        'io.kontena.health_check.port' => '1234',
        'io.kontena.health_check.timeout' => '10',
        'io.kontena.health_check.interval' => '30',
        'io.kontena.health_check.initial_delay' => '20',
      }
        
      allow(container).to receive(:labels).and_return(labels)
      allow(container).to receive(:overlay_cidr).and_return('1.2.3.4/16')
      expect(subject.wrapped_object).to receive(:every).with(30).and_yield
      expect(subject.wrapped_object).to receive(:sleep).with(20)
      expect(subject.wrapped_object).to receive(:check_tcp_status).with('1.2.3.4', 1234, 10).twice.and_return({})
      expect {
        subject.start
      }.to change {queue.size}.by (2) # runs check after initial delay and once within the every block
    end
  end

  describe '#check_http_status' do

    let(:headers) {
      {"User-Agent"=>"Kontena-Agent/#{Kontena::Agent::VERSION}"}
    }
    
    it 'returns healthy status' do
      response = double
      allow(response).to receive(:status).and_return(200)
      expect(Excon).to receive(:get).with('http://1.2.3.4:8080/health', {:connect_timeout=>10, :headers=>headers}).and_return(response)
      health_status = subject.check_http_status('1.2.3.4', 8080, '/health', 10)
      expect(health_status[:data]['status']).to eq('healthy')
      expect(health_status[:data]['status_code']).to eq(200)
    end
    
    it 'returns unhealthy status when response status not 200' do
      response = double
      allow(response).to receive(:status).and_return(500)
      expect(Excon).to receive(:get).with('http://1.2.3.4:8080/health', {:connect_timeout=>10, :headers=>headers}).and_return(response)
      health_status = subject.check_http_status('1.2.3.4', 8080, '/health', 10)
      expect(health_status[:data]['status']).to eq('unhealthy')
      expect(health_status[:data]['status_code']).to eq(500)
    end

    it 'returns unhealthy status when connection timeouts' do
      expect(Excon).to receive(:get).with('http://1.2.3.4:8080/health', {:connect_timeout=>10, :headers=>headers}).and_raise(Excon::Errors::Timeout)
      health_status = subject.check_http_status('1.2.3.4', 8080, '/health', 10)
      expect(health_status[:data]['status']).to eq('unhealthy')
    end

    it 'returns unhealthy status when connection fails with weird error' do
      expect(Excon).to receive(:get).with('http://1.2.3.4:8080/health', {:connect_timeout=>10, :headers=>headers}).and_raise(Excon::Errors::Error)
      health_status = subject.check_http_status('1.2.3.4', 8080, '/health', 10)
      expect(health_status[:data]['status']).to eq('unhealthy')
    end

  end

  describe '#check_tcp_status' do
    
    it 'returns healthy status' do
      socket = spy
      expect(TCPSocket).to receive(:new).with('1.2.3.4', 3306).and_return(socket)
      health_status = subject.check_tcp_status('1.2.3.4', 3306, 10)
      expect(health_status[:data]['status']).to eq('healthy')
      expect(health_status[:data]['status_code']).to eq('open')
    end
    
    it 'returns unhealthy status when cannot open socket' do
      expect(TCPSocket).to receive(:new).with('1.2.3.4', 3306).and_raise(Errno::ECONNREFUSED)
      health_status = subject.check_tcp_status('1.2.3.4', 3306, 10)
      expect(health_status[:data]['status']).to eq('unhealthy')
      expect(health_status[:data]['status_code']).to eq('closed')
    end

    it 'returns unhealthy status when connection timeouts' do
      expect(TCPSocket).to receive(:new).with('1.2.3.4', 3306) {sleep 1.5}
      health_status = subject.check_tcp_status('1.2.3.4', 3306, 1)
      expect(health_status[:data]['status']).to eq('unhealthy')
      expect(health_status[:data]['status_code']).to eq('closed')
    end

    it 'returns unhealthy status when connection fails with weird error' do
      expect(TCPSocket).to receive(:new).with('1.2.3.4', 3306).and_raise(Excon::Errors::Error)
      health_status = subject.check_tcp_status('1.2.3.4', 3306, 10)
      expect(health_status[:data]['status']).to eq('unhealthy')
    end

  end
end
