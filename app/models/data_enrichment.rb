class DataEnrichment < ApplicationRecord
  belongs_to :enrichable, polymorphic: true

  enum :source, { rule: "rule", plaid: "plaid", exchange_rate_host: "exchange_rate_host", ai: "ai" }
end
