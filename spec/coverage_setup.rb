# frozen_string_literal: true

require 'coverage'
require 'coverage.so'
require 'fileutils'
require 'json'
ENV['SIMPLECOV_NO_DEFAULTS'] = 'true'
require 'simplecov'

UNDERCOVER_REPORT_PATH = 'coverage/undercover.json'

Coverage.start(lines: true) unless Coverage.running?
SimpleCov.const_set(:Coverage, Coverage) unless SimpleCov.const_defined?(:Coverage, false)
SimpleCov::Configuration.const_set(:Coverage, Coverage) unless SimpleCov::Configuration.const_defined?(:Coverage, false)

class NullCoverageFormatter
  def format(_result); end
end

def write_undercover_coverage_json
  coverage = Coverage.peek_result.to_h.each_with_object({}) do |(path, data), output|
    next unless path.start_with?("#{SimpleCov.root}/")

    relative_path = path.delete_prefix("#{SimpleCov.root}/")
    output[relative_path] = { 'lines' => data.fetch(:lines) }
  end

  FileUtils.mkdir_p(File.dirname(UNDERCOVER_REPORT_PATH))
  File.write(
    UNDERCOVER_REPORT_PATH,
    JSON.pretty_generate({ 'meta' => {}, 'coverage' => coverage, 'groups' => {} })
  )
end

SimpleCov.formatter = NullCoverageFormatter

SimpleCov.start do
  track_files '{lib/**/*.rb,exe/rails-mmd}'
  add_filter '/spec/'
end

at_exit { write_undercover_coverage_json if Coverage.running? }
