# frozen_string_literal: true

module RailsMmd
  # Validates and resolves project-root-relative output directories.
  class OutputDirectory
    Result = Struct.new(:path, :relative_path, :reason, keyword_init: true) do
      def valid?
        reason.nil?
      end
    end

    DRIVE_OR_UNC_PATTERN = /\A(?:[A-Za-z]:|\\\\)/
    SAFE_RELATIVE_PATH_PATTERN = %r{\A[A-Za-z0-9._/-]+\z}

    def initialize(project_root:)
      @project_root = Pathname(project_root).expand_path
      @project_root_real = @project_root.realpath
    end

    def resolve(value)
      text = value.to_s
      reason = lexical_rejection_reason(text)
      return invalid(reason) if reason

      relative_path = normalize(text)
      return invalid('normalizes to project root') if relative_path == '.'
      return invalid('escapes project root') if relative_path.start_with?('../') || relative_path == '..'

      absolute_path = project_root.join(relative_path)
      return invalid('symlink escapes project root') unless inside_project_root?(absolute_path)

      Result.new(path: absolute_path, relative_path: relative_path)
    end

    private

    attr_reader :project_root, :project_root_real

    def lexical_rejection_reason(text)
      return 'is empty' if text.empty?
      return 'contains NUL' if text.include?("\u0000")
      return 'contains backslash' if text.include?('\\')
      return 'uses drive or UNC form' if text.match?(DRIVE_OR_UNC_PATTERN)
      return 'is absolute' if Pathname(text).absolute?

      'contains unsupported characters' unless text.match?(SAFE_RELATIVE_PATH_PATTERN)
    end

    def normalize(text)
      Pathname(text).cleanpath.to_s
    end

    def inside_project_root?(absolute_path)
      existing = closest_existing_path(absolute_path)
      relative = existing.realpath.relative_path_from(project_root_real).to_s
      relative == '.' || !relative.start_with?('..')
    rescue Errno::ENOENT
      false
    end

    def closest_existing_path(path)
      current = Pathname(path)
      current = current.parent until current.exist?
      current
    end

    def invalid(reason)
      Result.new(reason: reason)
    end
  end
end
