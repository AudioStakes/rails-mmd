# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'tmpdir'

module RailsMmd
  # Validates and resolves project-root-relative output directories.
  # rubocop:disable Metrics/ClassLength
  class OutputDirectory
    Result = Struct.new(:path, :relative_path, :reason, keyword_init: true) do
      def valid?
        reason.nil?
      end
    end

    DRIVE_OR_UNC_PATTERN = /\A(?:[A-Za-z]:|\\\\)/
    SAFE_RELATIVE_PATH_PATTERN = %r{\A[A-Za-z0-9._/-]+\z}
    MANAGED_PATH_PATTERN = /
      \A(?:
        global\.diagnostics\.json |
        [a-z][a-z0-9_]*\.(?:diagnostics\.json|(?:er|class)\.mmd|(?:er|class)\.render_plan\.json)
      )\z
    /x

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

    def publish!(result, selected_domain_ids:)
      raise ArgumentError, 'output directory is unresolved' unless result&.valid? && result.path

      output_path = result.path
      raise ArgumentError, 'output path escapes project root' unless inside_project_root?(output_path)

      output_path.mkpath
      ensure_inside_project_root!(output_path)
      plan = yield
      ensure_managed_plan!(plan, selected_domain_ids)
      write_plan(output_path, plan, selected_domain_ids)
      plan.keys.sort
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

    def write_plan(output_path, plan, selected_domain_ids)
      ensure_safe_replacement_set!(output_path, plan, selected_domain_ids)
      Dir.mktmpdir('.rails-mmd-', output_path.to_s) do |tmp|
        tmp_path = Pathname(tmp)
        plan.each { |relative_path, content| tmp_path.join(relative_path).write(content) }
        ensure_inside_project_root!(output_path)
        ensure_safe_replacement_set!(output_path, plan, selected_domain_ids)
        replace_plan_files(output_path, tmp_path, plan, selected_domain_ids)
      end
    end

    def replace_plan_files(output_path, tmp_path, plan, selected_domain_ids)
      Dir.mktmpdir('.rails-mmd-backup-', output_path.to_s) do |backup|
        backup_path = Pathname(backup)
        published_paths = []
        backup_existing_files(output_path, backup_path, selected_domain_ids)
        move_plan_files(output_path, tmp_path, plan, published_paths)
      rescue StandardError
        rollback_replacement(output_path, backup_path, published_paths)
        raise
      end
    end

    def backup_existing_files(output_path, backup_path, selected_domain_ids)
      scoped_managed_paths(output_path, selected_domain_ids).each do |path|
        ensure_safe_target!(output_path, path.basename.to_s)
        FileUtils.mv(path.to_s, backup_path.join(path.basename).to_s)
      end
    end

    def move_plan_files(output_path, tmp_path, plan, published_paths)
      plan.each_key do |relative_path|
        replace_file(output_path, tmp_path, relative_path)
        published_paths << relative_path
      end
    end

    def rollback_replacement(output_path, backup_path, published_paths)
      published_paths.each do |relative_path|
        target = output_path.join(relative_path)
        target.delete if target.file? && !target.symlink?
      end
      backup_path.children.each do |path|
        ensure_safe_target!(output_path, path.basename.to_s)
        FileUtils.mv(path.to_s, output_path.join(path.basename).to_s)
      end
    end

    def ensure_managed_plan!(plan, selected_domain_ids)
      plan.each_key do |relative_path|
        unless relative_path.is_a?(String) && relative_path.match?(MANAGED_PATH_PATTERN) &&
               scoped_managed_path?(relative_path, selected_domain_ids)
          raise ArgumentError, 'output plan path is unmanaged'
        end
      end
    end

    def ensure_safe_replacement_set!(output_path, plan, selected_domain_ids)
      scoped_managed_paths(output_path, selected_domain_ids).each do |path|
        ensure_safe_target!(output_path, path.basename.to_s)
      end
      plan.each_key { |relative_path| ensure_safe_target!(output_path, relative_path) }
    end

    def scoped_managed_paths(output_path, selected_domain_ids)
      output_path.children.select do |path|
        path.basename.to_s.match?(MANAGED_PATH_PATTERN) &&
          scoped_managed_path?(path.basename.to_s, selected_domain_ids)
      end
    end

    def scoped_managed_path?(name, selected_domain_ids)
      return true if name == 'global.diagnostics.json'

      selected_domain_ids.any? { |domain_id| name.start_with?("#{domain_id}.") }
    end

    def replace_file(output_path, tmp_path, relative_path)
      ensure_inside_project_root!(output_path)
      ensure_safe_target!(output_path, relative_path)
      FileUtils.mv(tmp_path.join(relative_path).to_s, output_path.join(relative_path).to_s)
    end

    def ensure_safe_target!(output_path, relative_path)
      target = output_path.join(relative_path)
      raise ArgumentError, 'output target is symlink' if target.symlink?
      raise ArgumentError, 'output target is not a regular file' if target.exist? && !target.file?

      ensure_inside_project_root!(target.parent)
    end

    def ensure_inside_project_root!(path)
      relative = path.realpath.relative_path_from(project_root_real).to_s
      raise ArgumentError, 'output path escapes project root' if relative.start_with?('..')
    end

    def invalid(reason)
      Result.new(reason: reason)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
