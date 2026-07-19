# frozen_string_literal: true

require 'yaml'
require 'rails_mmd/diagnostic_factory'
require 'rails_mmd/output_directory'
require 'rails_mmd/redactor'
require 'rails_mmd/schema_validator'

module RailsMmd
  # Loads and resolves the P0 YAML configuration contract without exposing CLI routing.
  # rubocop:disable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength
  class Config
    DEFAULT_CONFIG_PATH = 'rails_mmd.yml'
    DEFAULT_OUTPUT = {
      'directory' => 'docs/rails_mmd',
      'format' => 'both',
      'attributes' => 'keys',
      'direction' => 'LR'
    }.freeze
    DOMAIN_ID_PATTERN = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*\z/
    VALID_FORMATS = %w[er class both].freeze
    EXIT_CONTRACT_ERROR = 2

    CliOptions = Struct.new(:config_path, :output_dir, :domain, :format, keyword_init: true)
    Domain = Struct.new(:domain_id, :include_models, :exclude_models, keyword_init: true)
    Output = Struct.new(:directory, :path, :format, :attributes, :direction, :sources, keyword_init: true)
    Resolved = Struct.new(:config_path, :domains, :output, :selected_domain_ids, keyword_init: true)
    Result = Struct.new(:config, :diagnostics, :exit_code, keyword_init: true) do
      def success?
        diagnostics.empty?
      end
    end

    def initialize(project_root: Dir.pwd, validator: SchemaValidator.new, redactor: nil)
      @project_root = Pathname(project_root).expand_path
      @validator = validator
      @redactor = redactor || Redactor.new(project_root: @project_root)
      @diagnostic_factory = DiagnosticFactory.new(redactor: @redactor)
      @output_directory = OutputDirectory.new(project_root: @project_root)
    end

    def load(cli_options: CliOptions.new)
      config_path = resolve_config_path(cli_options.config_path)
      return failure(config_not_found(config_path)) unless config_path.file?

      data = safe_load(config_path)
      return failure(config_schema_invalid(config_path, 'config', 'must be a YAML mapping')) unless data.is_a?(Hash)

      output_directory_error = configured_output_directory_error(data, cli_options)
      return failure(output_directory_error) if output_directory_error

      schema_errors = validator.errors(:config, data_for_schema_validation(data, cli_options))
      unless schema_errors.empty?
        return failure(config_schema_invalid(config_path, field_path(schema_errors.first),
                                             'does not match config schema'))
      end

      build_config(config_path, data, cli_options)
    rescue Psych::Exception => e
      failure(config_schema_invalid(config_path, 'config', e.message))
    end

    private

    attr_reader :diagnostic_factory, :output_directory, :project_root, :validator

    def build_config(config_path, data, cli_options)
      domains = build_domains(data.fetch('domains'))
      output = build_output(data.fetch('output', {}), cli_options)
      unless output.fetch(:directory_result).valid?
        return failure(output_directory_invalid(output.fetch(:directory_result),
                                                output.fetch(:directory_source)))
      end
      unless VALID_FORMATS.include?(output.fetch(:format))
        return failure(config_schema_invalid(config_path, '$.cli.format',
                                             'must be er, class, or both'))
      end

      unless valid_domain_selection?(cli_options.domain)
        return failure(config_schema_invalid(config_path, '$.cli.domain',
                                             'must match domain ID grammar'))
      end

      selected_domain_ids = selected_domain_ids(domains, cli_options.domain)
      if selected_domain_ids.nil?
        return failure(diagnostic_factory.build(
                         code: 'CONFIG_DOMAIN_NOT_FOUND',
                         message: "Unknown domain #{cli_options.domain}",
                         subject_id: "domain:#{cli_options.domain}",
                         metadata: { domain_id: cli_options.domain.to_s }
                       ))
      end

      success(config_path, domains, output, selected_domain_ids)
    end

    def build_domains(domain_data)
      domain_data.to_h do |domain_id, domain|
        [
          domain_id,
          Domain.new(
            domain_id: domain_id,
            include_models: domain.fetch('include_models'),
            exclude_models: domain.fetch('exclude_models', [])
          )
        ]
      end
    end

    def build_output(data, cli_options)
      directory_source = cli_options.output_dir.nil? ? '$.output.directory' : '$.cli.output_dir'
      directory = cli_options.output_dir || data.fetch('directory', DEFAULT_OUTPUT.fetch('directory'))
      format = cli_options.format || data.fetch('format', DEFAULT_OUTPUT.fetch('format'))

      {
        directory_result: output_directory.resolve(directory),
        directory_source: directory_source,
        format: format,
        attributes: data.fetch('attributes', DEFAULT_OUTPUT.fetch('attributes')),
        direction: data.fetch('direction', DEFAULT_OUTPUT.fetch('direction')),
        sources: {
          'directory' => source_for(cli_options.output_dir, data, 'directory'),
          'format' => source_for(cli_options.format, data, 'format'),
          'attributes' => data.key?('attributes') ? 'config' : 'default',
          'direction' => data.key?('direction') ? 'config' : 'default'
        }
      }
    end

    def selected_domain_ids(domains, selected_domain)
      return domains.keys if selected_domain.nil?
      return [selected_domain] if domains.key?(selected_domain)

      nil
    end

    def success(config_path, domains, output_data, selected_domain_ids)
      directory = output_data.fetch(:directory_result)
      output = Output.new(
        directory: directory.relative_path,
        path: directory.path,
        format: output_data.fetch(:format),
        attributes: output_data.fetch(:attributes),
        direction: output_data.fetch(:direction),
        sources: output_data.fetch(:sources)
      )
      config = Resolved.new(config_path: config_path, domains: domains, output: output,
                            selected_domain_ids: selected_domain_ids)

      Result.new(config: config, diagnostics: [], exit_code: 0)
    end

    def failure(diagnostic)
      Result.new(config: nil, diagnostics: [diagnostic], exit_code: EXIT_CONTRACT_ERROR)
    end

    def config_not_found(config_path)
      diagnostic_factory.build(
        code: 'CONFIG_NOT_FOUND',
        message: "Config file not found: #{display_path(config_path)}",
        subject_id: 'config',
        metadata: { config_path: display_path(config_path) }
      )
    end

    def config_schema_invalid(config_path, field_path_value, reason)
      diagnostic_factory.build(
        code: 'CONFIG_SCHEMA_INVALID',
        message: "Invalid config #{display_path(config_path)}: #{reason}",
        subject_id: 'config',
        metadata: { config_path: display_path(config_path), field_path: field_path_value }
      )
    end

    def output_directory_invalid(result, field_path_value)
      diagnostic_factory.build(
        code: 'OUTPUT_DIRECTORY_INVALID',
        message: "Invalid output directory: #{result.reason}",
        subject_id: 'output.directory',
        metadata: { field_path: field_path_value, reason: result.reason }
      )
    end

    def data_for_schema_validation(data, cli_options)
      data = deep_dup(data)
      output = data['output']
      return data unless output.is_a?(Hash)

      output.delete('directory') unless cli_options.output_dir.nil?
      output.delete('format') unless cli_options.format.nil?
      data
    end

    def configured_output_directory_error(data, cli_options)
      return if cli_options.output_dir

      output = data['output']
      return unless output.is_a?(Hash) && output.key?('directory') && output.fetch('directory').is_a?(String)

      result = output_directory.resolve(output.fetch('directory'))
      output_directory_invalid(result, '$.output.directory') unless result.valid?
    end

    def resolve_config_path(value)
      Pathname(value || DEFAULT_CONFIG_PATH).then do |path|
        path.absolute? ? path : project_root.join(path)
      end
    end

    def display_path(path)
      relative = Pathname(path).expand_path.relative_path_from(project_root).to_s
      return relative unless relative.start_with?('..')

      DEFAULT_CONFIG_PATH
    end

    def safe_load(path)
      YAML.safe_load(path.read, permitted_classes: [], permitted_symbols: [], aliases: false)
    end

    def field_path(error)
      pointer = error&.fetch('data_pointer', nil).to_s
      return '$' if pointer.empty?

      "$.#{pointer.delete_prefix('/').tr('/', '.')}"
    end

    def source_for(cli_value, config_data, key)
      return 'cli' unless cli_value.nil?

      config_data.key?(key) ? 'config' : 'default'
    end

    def valid_domain_selection?(domain)
      domain.nil? || domain.match?(DOMAIN_ID_PATTERN)
    end

    def deep_dup(value)
      case value
      when Hash
        value.transform_values { |item| deep_dup(item) }
      when Array
        value.map { |item| deep_dup(item) }
      else
        value
      end
    end
  end
  # rubocop:enable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength
end
