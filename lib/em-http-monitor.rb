require 'eventmachine'
require 'em-http'
require 'json'
require 'ftools'

module EventMachine
  module Http
    class MonitorFactory
      
      MockNotFoundError = Class.new(RuntimeError)
      
      OriginalHttpRequest = EM::HttpRequest unless const_defined?(:OriginalHttpRequest)
      MockHttpRequest = EM::MockHttpRequest unless const_defined?(:MockHttpRequest)

      class FakeHttpClient < EM::HttpClient
        attr_writer :response
        attr_reader :data
        def setup(response, uri)
          @uri = uri
          if response == :fail
            fail(self)
          else
            original_receive_data(response)
            succeed(self)
          end
        end

        def unbind
        end
        
        def close_connection
        end
      end
      
      def debug(out = STDERR)
        activate
        install StreamOutputter.new(out)
      end
      
      def dump(path)
        activate
        install FileOutputter.new(path)
      end
      
      def clean_and_dump(path)
        activate
        outputter = FileOutputter.new(path)
        outputter.reset
        install outputter
      end
      
      def use_and_dump(path)
        activate
        install MockingFileOutputter.new(path)
      end
      
      def use(path)
        activate
        install FailingMockingFileOutputter.new(path)
      end
      
      def deactivate
        decativate_mocks
        deactivate_methods
      end
      
      def inform_receive(client, data)
        @app.receive(client, data)
      end
      
      def inform_send(client, data)
        @app.send(client, data)
      end
      
      def install(app)
        @app = app
      end
      
      def installed
        @app
      end
      
      protected
      
      def decativate_mocks
      end
      
      def activate
        EM::HttpClient.send(:class_eval, "
unless method_defined?(:original_receive_data)
  alias_method :original_receive_data, :receive_data
  alias_method :original_send_data, :send_data

  def receive_data(data)
    EM::Http::Monitor.inform_receive(self, data) and original_receive_data(data)
  end

  def send_data(data)
    EM::Http::Monitor.inform_send(self, data) and original_send_data(data)
  end
end
        ", __FILE__, __LINE__)
        
        EM::HttpRequest.send(:class_eval, <<-HERE_DOC, __FILE__, __LINE__)
unless method_defined?(:original_send_request)
  include HttpEncoding
  
  alias_method :original_send_request, :send_request
  def send_request(&blk)
    uri = encode_query(@req.uri, @req.options[:query])
    verb = @req.method
    host = @req.uri.host
    if EM::Http::Monitor.installed.respond_to?(:find_mock) and data = EM::Http::Monitor.installed.find_mock(verb, uri, host)
      client = FakeHttpClient.new(nil)
      client.setup(data, @req.uri)
      client
    else
      original_send_request(&blk)
    end
  rescue MockNotFoundError
    client = FakeHttpClient.new(nil)
    client.setup(:fail, @req.uri)
    client
  end
end
        HERE_DOC
        
      end
      
      def deactivate_methods
        EM::HttpClient.send(:class_eval, "
if method_defined?(:original_receive_data)
  alias_method :receive_data, :original_receive_data
  alias_method :send_data, :original_send_data
  undef_method :original_receive_data
  undef_method :original_send_data
end  
        ", __FILE__, __LINE__)
        EM::HttpRequest.send(:class_eval, "
if method_defined?(:original_send_request)
  alias_method :send_request, :original_send_request
  undef_method :original_send_request
end  
        ", __FILE__, __LINE__)
      end
      
      class StreamOutputter
        def initialize(stream)
          @stream = stream
          @stream.sync = true
        end

        def send(client, data)
          @stream << "#{client.object_id} >> #{data}"
          @stream << "\n" unless data[-1] == 13 or data[-1] == 10
          true
        end

        def receive(client, data)
          @stream << "#{client.object_id} << #{data}"
          @stream << "\n" unless data[-1] == 13 or data[-1] == 10
          true
        end
      end

      class FileOutputter
        def initialize(file)
          @file = file
          @fh = File.new(file, 'a')
          @fh.sync = true
        end

        def reset
          File.truncate(@file, 0)
        end

        def send(client, data)
          @fh.puts({:mode => 'send', :id => client.object_id, :data => data}.to_json)
          @fh.fsync
          true
        end

        def receive(client, data)
          @fh.puts({:mode => 'receive', :id => client.object_id, :data => data}.to_json)
          @fh.fsync
          true
        end
      end
      
      class MockingFileOutputter < FileOutputter
        
        attr_reader :file
        
        class MockingData
          attr_reader :sent, :received
          
          def initialize
            @sent, @received = '', ''
          end
        end
        
        
        def initialize(file)
          @file = file
          if File.exist?(file)
            @mock_data = File.read(file).each_line.inject([]) do |hash, line|
              data = JSON.parse(line)
              if entry = hash.assoc(data['id'])
                entry = entry.last
              else
                entry = MockingData.new
                hash << [data['id'], entry]
              end
              case data['mode']
              when 'send'
                entry.sent << data['data']
              when 'receive'
                entry.received << data['data']
              else
                raise
              end
              hash
            end
          end
          super
        end

        def find_mock(verb, uri, host)
          if @mock_data and matching_data = @mock_data.find{ |d| d.last.sent[/^#{Regexp.quote(verb.to_s.upcase)} #{Regexp.quote(uri)} HTTP\/1\.[01][\r\n]/] and d.last.sent[/(Host:\s*#{Regexp.quote(host)})[\r\n]/] }
            @mock_data.delete(matching_data).last.received
          end
        end
      end
      
      class FailingMockingFileOutputter < MockingFileOutputter
        def find_mock(verb, uri, host)
          super or raise(MockNotFoundError, "Cannot find mock for #{verb} #{uri} #{host} in #{file}")
        end
      end
    end
  end
end

EM::Http::Monitor = EM::Http::MonitorFactory.new