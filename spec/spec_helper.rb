# frozen_string_literal: true

require "bundler/setup"
require "rubyagents"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Suppress UI output during tests
  config.before do
    allow(Rubyagents::UI).to receive(:welcome)
    allow(Rubyagents::UI).to receive(:step_header)
    allow(Rubyagents::UI).to receive(:thought)
    allow(Rubyagents::UI).to receive(:code)
    allow(Rubyagents::UI).to receive(:observation)
    allow(Rubyagents::UI).to receive(:error)
    allow(Rubyagents::UI).to receive(:plan)
    allow(Rubyagents::UI).to receive(:step_metrics)
    allow(Rubyagents::UI).to receive(:run_summary)
    allow(Rubyagents::UI).to receive(:final_answer)
    allow(Rubyagents::UI).to receive(:spinner).and_return(
      instance_double(Rubyagents::UI::Spinner, start: nil, stop: nil)
    )
  end
end
