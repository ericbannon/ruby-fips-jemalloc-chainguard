# frozen_string_literal: true

require_relative "jemalloc_check"

run lambda { |_env|
  body = JemallocCheck.info_json
  [200, { "Content-Type" => "application/json", "Content-Length" => body.bytesize.to_s }, [body]]
}