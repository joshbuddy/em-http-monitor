$: << "#{File.dirname(__FILE__)}/../lib"

require 'rubygems'
require 'eventmachine'
require 'em-http-monitor'
require 'fileutils'

DUMP_FILE = '/tmp/monitor_dump'

describe "em-http-monitor" do
  after(:each) do
    EM::Http::Monitor.deactivate
    FileUtils.rm_rf(DUMP_FILE)
  end

  it "should print debug info to the stream" do
    io = StringIO.new
    EM::Http::Monitor.debug(io)
    EM.run do
      http = EventMachine::HttpRequest.new("http://www.google.ca/").get :timeout => 2
  
      http.callback {
        io.rewind
        data = io.read
        data.should match(/>> GET \/ HTTP\/1\.1\r\n/)
        data.should match(/<< HTTP\/1\.1 200 OK\r\n/)
        EM.stop
      }
    end
  end
  
  it "should leave methods behind when it cleans up" do
    EM::Http::Monitor.debug(STDOUT)
    EM::HttpClient.instance_methods.should include('original_receive_data')
    EM::Http::Monitor.deactivate
    EM::HttpClient.instance_methods.should_not include('original_receive_data')
  end
  
  it "should dump requests to disk" do
    EM::Http::Monitor.dump(DUMP_FILE)
    EM.run do
      http = EventMachine::HttpRequest.new("http://www.google.ca/").get :timeout => 2
  
      http.callback {
        lines = File.read(DUMP_FILE).split("\n").map{|line| JSON.parse(line)}
        received_line = lines.shift
        received_line['mode'].should == 'send'
        received_line['data'].should match(/GET \/ HTTP\/1\.1\r\n/)
        lines.size.should >= 1
        lines.each {|line| line['mode'].should == 'receive' }
        lines.first['data'].should match(/HTTP\/1\.1 200 OK\r\n/)
        EM.stop
      }
    end
  end

  it "should use dumps to mock requests" do
    EM::Http::Monitor.use_and_dump("#{File.dirname(__FILE__)}/fixtures/monitor_dump")
    EM.run do
      http = EventMachine::HttpRequest.new("http://news.google.com/").get :timeout => 10
      http.callback {
        http.response.should == 'yupyupyup'
        http2 = EventMachine::HttpRequest.new("http://www.google.ca/").get :timeout => 10
        http2.callback {
          http2.response.should == 'heyheyhey'
          EM.stop
        }
        http2.errback { |err|
          p err
          fail
          EM.stop
        }
      }
      http.errback { |err|
        p err
        fail
        EM.stop
      }
    end
  end

  it "should only use dumps to mock requests" do
    EM::Http::Monitor.use("#{File.dirname(__FILE__)}/fixtures/monitor_dump")
    EM.run do
      http = EventMachine::HttpRequest.new("http://www.slashdot.org/").get :timeout => 10
      http.callback {
        fail
        EM.stop
      }
      http.errback { |err|
        1.should == 1
        EM.stop
      }
    end
  end

end