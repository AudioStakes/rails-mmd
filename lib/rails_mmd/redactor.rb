# frozen_string_literal: true

require 'pathname'
require 'uri'

module RailsMmd
  # Sanitizes free-form text before it can leave the process.
  # rubocop:disable Metrics/ClassLength
  class Redactor
    SECRET_KEY_PATTERN = /
      (?:password|passwd|secret|api[_-]?key|credential|database_url|(?:access|auth|refresh)[_-]?token)
    /ix
    URL_CREDENTIAL_PATTERN = %r{([a-z][a-z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@}i
    DRIVE_OR_UNC_PATTERN = %r{\b(?:[A-Za-z]:[\\/]|\\\\[^\\/\s]+[\\/][^\\/\s]+)}
    MERMAID_SECRET_KEY = /
      (?:
        password|passwd|secret|credential|token|pid|
        api\s*[_-]?\s*key|
        database\s*[_-]?\s*url|
        (?:access|auth|refresh)\s*[_-]?\s*token|
        generated\s*[_-]?\s*at|
        process\s*[_-]?\s*id|
        random\s*[_-]?\s*seed|
        raw\s*[_-]?\s*exception\s*[_-]?\s*backtrace
      )
    /ix
    MERMAID_FORBIDDEN_ASSIGNMENT = /[A-Za-z0-9_-]*#{MERMAID_SECRET_KEY}[A-Za-z0-9_-]*\s*(?::|=|\s+)\s*\S+/ix
    REDACTED_KEY_ASSIGNMENT = /[A-Za-z0-9_-]*\[REDACTED_KEY\][A-Za-z0-9_-]*\s*(?::|=|\s+)\s*\S+/
    URL_PATTERN = %r{\b[a-z][a-z0-9+.-]*://[^\s]+}i
    URL_PLACEHOLDER_PREFIX = "\uE000RAILSMMDURL"
    REDACTED_URL = '[REDACTED_URL]'
    MERMAID_CONTROL_TEXT = /[\r\n\t[:cntrl:]]+/
    CONTROL_SPLIT_ABSOLUTE_PATH =
      /(?<![A-Za-z0-9_])\/[^[:cntrl:]\s)\]}>;,:!?]+(?:[\r\n\t[:cntrl:]][^[:cntrl:]\s)\]}>;,:!?]*)*/
    STRUCTURED_PATTERNS = {
      ruby_constant: /\A[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*\z/,
      ruby_constant_label: /\A[A-Z][A-Za-z0-9_]*\z/,
      snake_identifier: /\A[a-z][a-z0-9_]*\z/
    }.freeze
    STRUCTURED_FALLBACK = 'X'

    class << self
      def sanitize_mermaid_free_text(value, sanitizer:)
        urls = []
        text = protect_urls(value.to_s.delete("\u0000"), urls)
        text = text.gsub(CONTROL_SPLIT_ABSOLUTE_PATH, '[REDACTED_PATH]')
        text = text.gsub(MERMAID_CONTROL_TEXT, ' ')
        text = text.gsub(MERMAID_FORBIDDEN_ASSIGNMENT, '[REDACTED]')
        text = sanitizer.sanitize(text).gsub(REDACTED_KEY_ASSIGNMENT, '[REDACTED]')
        restore_urls(text, urls).gsub(/\s+/, ' ').strip
      end

      def sanitize_mermaid_structured(value, grammar:)
        text = value.to_s.delete("\u0000").gsub(MERMAID_CONTROL_TEXT, ' ').gsub(/\s+/, ' ').strip
        return STRUCTURED_FALLBACK unless STRUCTURED_PATTERNS.fetch(grammar).match?(text)

        text
      end

      private

      def protect_urls(text, urls)
        text.gsub(URL_PATTERN) do |_url|
          urls << REDACTED_URL
          "#{URL_PLACEHOLDER_PREFIX}#{urls.length - 1}"
        end
      end

      def restore_urls(text, urls)
        urls.each_with_index.reduce(text) do |output, (url, index)|
          output.gsub("#{URL_PLACEHOLDER_PREFIX}#{index}", url)
        end
      end
    end

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
        sanitize_hash(value)
      else
        value
      end
    end

    private

    attr_reader :project_root, :env_values

    def sanitize_hash(value)
      value.to_h do |key, item|
        [sanitize(key), sanitize_object(item)]
      end
    end

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
  # rubocop:enable Metrics/ClassLength
end
