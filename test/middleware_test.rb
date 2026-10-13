require "test_helper"

class MiddlewareTest < Minitest::Test
  HTML = "<html><head></head><body>hi</body></html>"

  class ClosableBody
    attr_reader :closed

    def each
      yield HTML
    end

    def close
      @closed = true
    end
  end

  def test_injects_scripts_into_html_head
    _status, headers, body = call_middleware(ClosableBody.new)

    assert_includes body.each.to_a.join, "<script id=\"livereload\"></script></head>"
    assert_equal body.each.to_a.join.bytesize.to_s, headers["Content-Length"]
  end

  def test_closing_an_injected_response_closes_the_original_body
    original = ClosableBody.new
    _status, _headers, body = call_middleware(original)

    body.close

    assert original.closed, "the original response body must be closed"
  end

  def test_untouched_response_keeps_the_original_body
    original = ClosableBody.new
    _status, _headers, body = call_middleware(original, content_type: "application/json")

    assert_same original, body
  end

  def test_next_request_does_not_inherit_log_tags_after_injection
    log = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(log))
    Rails.logger = logger

    # Livereload outside the logger is its default position in a Rails app.
    logged = Rails::Rack::Logger.new(->(_env) { [200, {"content-type" => "text/html"}, ClosableBody.new] }, [:request_id])
    stack = middleware_for(logged)

    ["first-id", "second-id"].each do |id|
      _status, _headers, body = stack.call(Rack::MockRequest.env_for("/", "action_dispatch.request_id" => id))
      body.each { |_| }
      body.close if body.respond_to?(:close) # servers close only bodies that respond to it
    end

    log.truncate(0)
    log.rewind
    logger.info("after both requests")

    assert_equal "after both requests\n", log.string
  end

  private

  def call_middleware(body, content_type: "text/html")
    app = ->(_env) { [200, {"content-type" => content_type}, body] }
    middleware_for(app).call(Rack::MockRequest.env_for("/"))
  end

  def middleware_for(app)
    middleware = Hotwire::Livereload::Middleware.new(app)
    middleware.define_singleton_method(:livereload_scripts) { |_request| "<script id=\"livereload\"></script>" }
    middleware
  end
end
