# frozen_string_literal: true

require 'rake'

RSpec.describe 'Rake tasks' do
  before(:all) do
    @previous_application = Rake.application
    Rake.application = Rake::Application.new
    load File.expand_path('../Rakefile', __dir__)
  end

  after(:all) do
    Rake.application = @previous_application
  end

  it 'runs specs and build by default' do
    expect(Rake::Task[:default].prerequisites).to eq(%w[spec build])
  end
end
