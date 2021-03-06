require 'raven/version'
require 'raven/backtrace'
require 'raven/processor'
require 'raven/processor/sanitizedata'
require 'raven/processor/removecircularreferences'
require 'raven/processor/utf8conversion'
require 'raven/processor/cookies'
require 'raven/processor/post_data'
require 'raven/configuration'
require 'raven/context'
require 'raven/client'
require 'raven/event'
require 'raven/logger'
require 'raven/interfaces/message'
require 'raven/interfaces/exception'
require 'raven/interfaces/single_exception'
require 'raven/interfaces/stack_trace'
require 'raven/interfaces/http'
require 'raven/utils/deep_merge'
require 'raven/instance'

require 'forwardable'

module Raven
  AVAILABLE_INTEGRATIONS = %w[delayed_job railties sidekiq rack rake].freeze

  class << self
    extend Forwardable

    def instance
      @instance ||= Raven::Instance.new
    end

    def_delegators :instance, :client=, :configuration=, :context, :logger, :configuration,
                   :client, :report_status, :configure, :send_event, :capture, :capture_type,
                   :last_event_id, :should_capture?, :annotate_exception, :user_context,
                   :tags_context, :extra_context, :rack_context

    def_delegator :instance, :report_status, :report_ready
    def_delegator :instance, :capture_type, :capture_message
    def_delegator :instance, :capture_type, :capture_exception
    # For cross-language compatibility
    def_delegator :instance, :capture_type, :captureException
    def_delegator :instance, :capture_type, :captureMessage
    def_delegator :instance, :annotate_exception, :annotateException
    def_delegator :instance, :annotate_exception, :annotate

    # Injects various integrations. Default behavior: inject all available integrations
    def inject
      inject_only(*Raven::AVAILABLE_INTEGRATIONS)
    end

    def inject_without(*exclude_integrations)
      include_integrations = Raven::AVAILABLE_INTEGRATIONS - exclude_integrations.map(&:to_s)
      inject_only(*include_integrations)
    end

    def inject_only(*only_integrations)
      only_integrations = only_integrations.map(&:to_s)
      integrations_to_load = Raven::AVAILABLE_INTEGRATIONS & only_integrations
      not_found_integrations = only_integrations - integrations_to_load
      if not_found_integrations.any?
        self.logger.warn "Integrations do not exist: #{not_found_integrations.join ', '}"
      end
      integrations_to_load &= Gem.loaded_specs.keys
      # TODO(dcramer): integrations should have some additional checks baked-in
      # or we should break them out into their own repos. Specifically both the
      # rails and delayed_job checks are not always valid (i.e. Rails 2.3) and
      # https://github.com/getsentry/raven-ruby/issues/180
      integrations_to_load.each do |integration|
        load_integration(integration)
      end
    end

    def load_integration(integration)
      require "raven/integrations/#{integration}"
    rescue Exception => error
      self.logger.warn "Unable to load raven/integrations/#{integration}: #{error}"
    end

    def rails_safely_prepend(module_name, opts = {})
      return if opts[:to].nil?
      if opts[:to].respond_to?(:prepend, true)
        opts[:to].send(:prepend, Raven::Rails::Overrides.const_get(module_name))
      else
        opts[:to].send(:include, Raven::Rails::Overrides.const_get("Old" + module_name))
      end
    end

    private

    def install_at_exit_hook(options)
      at_exit do
        if $!
          logger.debug "Caught a post-mortem exception: #{$!.inspect}"
          capture_exception($!, options)
        end
      end
    end
  end
end
