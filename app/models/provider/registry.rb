class Provider::Registry
  include ActiveModel::Validations

  Error = Class.new(StandardError)

  CONCEPTS = %i[exchange_rates securities llm]

  validates :concept, inclusion: { in: CONCEPTS }

  class << self
    def for_concept(concept)
      new(concept.to_sym)
    end

    def get_provider(name)
      send(name)
    rescue NoMethodError
      raise Error.new("Provider '#{name}' not found in registry")
    end

    def plaid_provider_for_region(region)
      region.to_sym == :us ? plaid_us : plaid_eu
    end

    private
      def stripe
        secret_key = ENV["STRIPE_SECRET_KEY"]
        webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]

        return nil unless secret_key.present? && webhook_secret.present?

        Provider::Stripe.new(secret_key:, webhook_secret:)
      end

      def synth
        api_key = ENV.fetch("SYNTH_API_KEY", Setting.synth_api_key)

        return nil unless api_key.present?

        Provider::Synth.new(api_key)
      end

      def plaid_us
        config = Rails.application.config.plaid

        return nil unless config.present?

        Provider::Plaid.new(config, region: :us)
      end

      def plaid_eu
        config = Rails.application.config.plaid_eu

        return nil unless config.present?

        Provider::Plaid.new(config, region: :eu)
      end

      def github
        Provider::Github.new
      end

      def openai
        # Check for standard OpenAI token OR if LM Studio is explicitly enabled
        openai_token_present = ENV.fetch("OPENAI_ACCESS_TOKEN", Setting.openai_access_token).present?
        lm_studio_enabled = ENV['USE_LM_STUDIO'] == 'true'

        return nil unless openai_token_present || lm_studio_enabled

        # Provider::Openai will handle its own token and settings based on ENV vars
        # Pass the standard OpenAI access token if available, otherwise it can be nil
        # if only LM Studio is being used (Provider::Openai handles this).
        access_token = ENV.fetch("OPENAI_ACCESS_TOKEN", Setting.openai_access_token)
        Provider::Openai.new(access_token)
      end
  end

  def initialize(concept)
    @concept = concept
    validate!
  end

  def providers
    available_providers.map { |p| self.class.send(p) }
  end

  def get_provider(name)
    provider_method = available_providers.find { |p| p == name.to_sym }

    raise Error.new("Provider '#{name}' not found for concept: #{concept}") unless provider_method.present?

    self.class.send(provider_method)
  end

  private
    attr_reader :concept

    def available_providers
      case concept
      when :exchange_rates
        %i[synth]
      when :securities
        %i[synth]
      when :llm
        %i[openai]
      else
        %i[synth plaid_us plaid_eu github openai]
      end
    end
end
