require "spec"
require "../src/robust_http"

# https://github.com/crystal-lang/crystal/blob/ad83832f1f5afa8e0cda7544e542dd4d48e3bb70/spec/std/http/client/client_spec.cr#L6-L23
class TestServer < TCPServer
  def self.open(host, port, read_time = 0)
    server = new(host, port)
    begin
      spawn do
        io = server.accept
        req_str = io.gets
        requested_code = req_str.nil? ? 400 : /^GET \/(\d\d\d) .+$/.match(req_str).not_nil![1].to_i32

        sleep read_time

        headers = HTTP::Headers.new.add("Content-Type", "text/plain")
        response = HTTP::Client::Response.new(requested_code, headers: headers, body: HTTP.default_status_message_for(requested_code))
        response.to_io(io)
        io.flush
      end

      yield server
    ensure
      server.close
    end
  end
end

class FailingTestServer < TCPServer
  def self.open(host, port, final_status, error_status = 500, succeed_after_attempts = 1, read_time = 0)
    server = new(host, port)
    retry_count = 0
    begin
      spawn do
        io = server.accept
        while true
          input = io.gets
          next unless input == "\r\n"  # End of HTTP request
          sleep read_time

          headers = HTTP::Headers.new.add("Content-Type", "text/plain")
          code = retry_count < succeed_after_attempts ? error_status : final_status
          response = HTTP::Client::Response.new(code, headers: headers, body: HTTP.default_status_message_for(code))
          response.to_io(io)
          io.flush
          retry_count += 1
          break if retry_count > succeed_after_attempts
        end
      end
      yield server
    ensure
      server.close
    end
    return retry_count
  end
end

describe RobustHTTP do
  it "returns upstream response when upstream server immediately returns 200 <= status_code <= 299" do
    TestServer.open("localhost", 0, 0) do |server|
      resp = RobustHTTP.exec("localhost", server.local_address.port, HTTP::Request.new("GET", "/200"), 1.0)
      resp.status_code.should eq(200)
      resp.body.should eq("OK")
    end
  end

  it "returns upstream response when upstream server immediately returns 400 <= status_code <= 499" do
    TestServer.open("localhost", 0, 0) do |server|
      resp = RobustHTTP.exec("localhost", server.local_address.port, HTTP::Request.new("GET", "/401"), 1.0)
      resp.status_code.should eq(401)
      resp.body.should eq("Unauthorized")
    end
  end

  it "returns upstream response when upstream server returns 200 <= status_code <= 299 before timeout" do
    server_delay = 0.1
    client_timeout = 0.4
    TestServer.open("localhost", 0, server_delay) do |server|
      resp = RobustHTTP.exec("localhost", server.local_address.port, HTTP::Request.new("GET", "/202"), client_timeout)
      resp.status_code.should eq(202)
      resp.body.should eq("Accepted")
    end
  end

  it "returns upstream response when upstream server returns 400 <= status_code <= 499 before timeout" do
    server_delay = 0.1
    client_timeout = 0.4
    TestServer.open("localhost", 0, server_delay) do |server|
      resp = RobustHTTP.exec("localhost", server.local_address.port, HTTP::Request.new("GET", "/400"), client_timeout)
      resp.status_code.should eq(400)
      resp.body.should eq("Bad Request")
    end
  end

  it "retries request if 5xx is received and timeout has not been reached" do
    retry_count = FailingTestServer.open("localhost", 0, 200, 500) do |server|
      RobustHTTP.exec("localhost", server.local_address.port, HTTP::Request.new("GET", "/"), 1.0)
    end
    retry_count.should eq(2)  # First one fails, second one succeeds
  end

  it "returns upstream response when upstream server returns 200 <= status_code <= 299 after retries" do
    FailingTestServer.open("localhost", 0, 200, 500, 2) do |server|
      resp = RobustHTTP.exec("localhost", server.local_address.port, HTTP::Request.new("GET", "/"), 1.0)
      resp.status_code.should eq(200)
      resp.body.should eq("OK")
    end
  end

  it "returns upstream response when upstream server returns 400 <= status_code <= 499 after retries" do
    FailingTestServer.open("localhost", 0, 400) do |server|
      resp = RobustHTTP.exec("localhost", server.local_address.port, HTTP::Request.new("GET", "/"), 1.0)
      resp.status_code.should eq(400)
      resp.body.should eq("Bad Request")
    end
  end

  it "returns 503 response if no response is received from upstream server before timeout" do
    server_delay = 0.2
    client_timeout = 0.1
    FailingTestServer.open("localhost", 0, 200, 500, 1, server_delay) do |server|
      resp = RobustHTTP.exec("localhost", server.local_address.port, HTTP::Request.new("GET", "/"), client_timeout)
      resp.status_code.should eq(503)
      resp.body.should eq("")
    end
  end

  it "returns 503 response if upstream server continues to send 5xxs until timeout" do
    FailingTestServer.open("localhost", 0, 200, 500, 5, 0.05) do |server|
      resp = RobustHTTP.exec("localhost", server.local_address.port, HTTP::Request.new("GET", "/"), 0.24)  # 0.24 < 5 * 0.05
      resp.status_code.should eq(503)
      resp.body.should eq("")
    end
  end
end