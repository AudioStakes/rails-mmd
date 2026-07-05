# frozen_string_literal: true

require 'digest'
require 'json/canonicalization'

module RailsMmd
  # RFC 8785/JCS canonical JSON helpers.
  module CanonicalJson
    module_function

    def dump(value)
      value.to_json_c14n
    end

    def digest_sha256(value)
      Digest::SHA256.hexdigest(dump(value))
    end
  end
end
