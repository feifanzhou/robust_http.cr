require "http/client"

module HTTP
  class Client
    class Response
      def request_error?
        (400..499).includes?(status_code)
      end

      def server_error?
        (500..599).includes?(status_code)
      end
    end
  end
end

struct Time
  struct Span
    def negative?
      self * -1 > self
    end
  end
end

class RobustHTTP
  def self.exec(host : String, port, request : HTTP::Request, timeout : Float)
    timeout_time = timeout.seconds.from_now
    client = HTTP::Client.new(host, port)
    attempt_count = 0
    while true
      begin
        remaining_time = timeout_time - Time.now
        return HTTP::Client::Response.new(503) if remaining_time.negative?

        attempt_count += 1
        client.connect_timeout = remaining_time * 0.3
        client.read_timeout = remaining_time * 0.7
        response = client.exec(request)

        if response.success? || response.request_error?
          client.close
          return response
        else
          sleep delay_after_attempt(attempt_count)
          next
        end
      rescue timeout : IO::Timeout
        sleep delay_after_attempt(attempt_count)
        next
      end
    end
  end

  private def self.delay_after_attempt(attempt_count)
    random = Random.rand(0.2) + 0.8  # Range from 0.8 – 1.2
    (2 ^ attempt_count) * random * 0.1  # seconds
  end
end