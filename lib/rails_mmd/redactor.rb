# frozen_string_literal: true

require 'uri'

module RailsMmd
  # Sanitizes free-form text before it can leave the process.
  class Redactor
    SECRET_KEY_PATTERN = /(?:password|passwd|token|secret|api[_-]?key|credential|database_url)/i
    URL_CREDENTIAL_PATTERN = %r{([a-z][a-z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@}i
    DRIVE_OR_UNC_PATTERN = %r{\b(?:[A-Za-z]:[\\/]|\\\\[^\\/\s]+[\\/][^\\/\s]+)}

    def initialize(project_root: Dir.pwd, env: ENV.to_h)
      @project_root = Pathname(project_root).expand_path
      @env_values = env.values.compact.map(&:to_s).select { |value| value.length >= 4 }.uniq
    end

    def sanitize(value)
      text = value.to_s.dup
      text = text.delete("\u0000")
      text = text.gsub(URL_CREDENTIAL_PATTERN, '\\1[REDACTED]@')
      text = text.gsub(DRIVE_OR_UNC_PATTERN, '[REDACTED_PATH]')
      text = redact_absolute_paths(text)
      text = redact_env_values(text)
      text.gsub(SECRET_KEY_PATTERN, '[REDACTED_KEY]')
    end

    def sanitize_object(value)
      case value
      when String
        sanitize(value)
      when Array
        value.map { |item| sanitize_object(item) }
      when Hash
        value.transform_values { |item| sanitize_object(item) }
      else
        value
      end
    end

    private

    attr_reader :project_root, :env_values

    def redact_env_values(text)
      env_values.reduce(text) { |output, value| output.gsub(value, '[REDACTED]') }
    end

    def redact_absolute_paths(text)
      text.gsub(%r{(?:/[\w.-]+){2,}}) do |path|
        display_path(path)
      end
    end

    def display_path(path)
      pathname = Pathname(path)
      expanded = pathname.expand_path
      relative = expanded.relative_path_from(project_root)
      return relative.to_s unless relative.to_s.start_with?('..')

      '[REDACTED_PATH]'
    end
  end
end
