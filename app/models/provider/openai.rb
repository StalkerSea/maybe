class Provider::Openai < Provider
  include LlmConcept

  # Subclass so errors caught in this provider are raised as Provider::Openai::Error
  Error = Class.new(Provider::Error)

  # Default model for LM Studio if not set in ENV
  DEFAULT_LM_STUDIO_MODEL = 'mistralai/mistral-7b-instruct-v0.3'.freeze
  # Default OpenAI model (from original code, adjust if needed)
  DEFAULT_OPENAI_MODEL = 'gpt-4.1'.freeze

  def self.current_models
    if ENV['USE_LM_STUDIO'] == 'true'
      [ENV.fetch('LM_STUDIO_MODEL_NAME', DEFAULT_LM_STUDIO_MODEL)]
    else
      # Assuming original was a single model, adjust if it was a list
      [DEFAULT_OPENAI_MODEL]
    end
  end

  def initialize(access_token)
    @use_lm_studio = ENV['USE_LM_STUDIO'] == 'true'

    token_to_use = if @use_lm_studio
                     ENV.fetch('LM_STUDIO_ACCESS_TOKEN', 'lm-studio') # LM Studio might not need a real token
                   else
                     access_token # Original OpenAI access token
                   end

    uri_base = if @use_lm_studio
                 ENV.fetch('LM_STUDIO_API_BASE_URL', 'http://localhost:1234/v1') # Default LM Studio URL
               else
                 nil # Default OpenAI API URL
               end

    client_options = { access_token: token_to_use }
    client_options[:uri_base] = uri_base if uri_base.present?
    # Some configurations might need organization_id to be nil for self-hosted endpoints
    # client_options[:organization_id] = nil if uri_base.present?

    @client = ::OpenAI::Client.new(**client_options)
  end

  def supports_model?(model)
    self.class.current_models.include?(model)
  end

  def auto_categorize(transactions: [], user_categories: [])
    with_provider_response do
      raise Error, "Too many transactions to auto-categorize. Max is 25 per request." if transactions.size > 25

      AutoCategorizer.new(
        client,
        transactions: transactions,
        user_categories: user_categories
      ).auto_categorize
    end
  end

  def auto_detect_merchants(transactions: [], user_merchants: [])
    with_provider_response do
      raise Error, "Too many transactions to auto-detect merchants. Max is 25 per request." if transactions.size > 25

      AutoMerchantDetector.new(
        client,
        transactions: transactions,
        user_merchants: user_merchants
      ).auto_detect_merchants
    end
  end

  def chat_response(prompt, model:, instructions: nil, functions: [], function_results: [], streamer: nil, previous_response_id: nil)
    with_provider_response do
      current_model_to_use = if @use_lm_studio
        ENV.fetch('LM_STUDIO_MODEL_NAME', DEFAULT_LM_STUDIO_MODEL)
      else
        model # Use the model parameter for standard OpenAI
      end

      unless supports_model?(current_model_to_use)
        raise Error, "Model #{current_model_to_use} not supported by current configuration."
      end

      chat_config = ChatConfig.new(
        functions: functions,
        function_results: function_results
      )

      collected_chunks = []
      stream_proxy = if streamer.present?
        proc do |chunk|
          # Assuming ChatStreamParser works for LM Studio's OpenAI-compatible stream
          parsed_chunk = ChatStreamParser.new(chunk).parsed
          unless parsed_chunk.nil?
            streamer.call(parsed_chunk)
            collected_chunks << parsed_chunk
          end
        end
      else
        nil
      end

      parameters = { model: current_model_to_use, stream: stream_proxy }

      if @use_lm_studio
        messages = []
        messages << { role: "system", content: instructions } if instructions.present?
        # Assuming chat_config.build_input(prompt) returns the user's message content (String).
        # If it builds a more complex structure (e.g., full message history), this part may need adjustment.
        messages << { role: "user", content: chat_config.build_input(prompt) }
        
        # Note: Handling of chat_config.function_results (tool/function call responses)
        # would need to be explicitly added to the `messages` array here if not
        # already incorporated by `chat_config.build_input(prompt)` in a way
        # that forms part of the user message.
        # For example:
        # chat_config.function_results.each do |result|
        #   messages << { role: "tool", tool_call_id: result.id, name: result.name, content: result.content }
        # end
        # This depends on the structure of `function_results` and how `ChatConfig` handles them.

        parameters[:messages] = messages
        parameters[:tools] = chat_config.tools if chat_config.tools.present?
      else
        # Original OpenAI parameters
        parameters[:input] = chat_config.build_input(prompt)
        parameters[:instructions] = instructions
        parameters[:tools] = chat_config.tools
        parameters[:previous_response_id] = previous_response_id
      end

      # Assuming client.responses.create can handle a :messages parameter
      # or is a wrapper around a method like client.chat that does.
      raw_response = client.responses.create(parameters: parameters)

      if stream_proxy.present?
        response_chunk = collected_chunks.find { |chunk| chunk.type == "response" }
        response_chunk&.data # Use safe navigation in case no response chunk is found
      else
        ChatParser.new(raw_response).parsed
      end
    end
  end

  private
    attr_reader :client, :use_lm_studio
end
