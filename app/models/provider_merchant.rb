class ProviderMerchant < Merchant
  enum :source, { plaid: "plaid", exchange_rate_host: "exchange_rate_host", ai: "ai" }

  validates :name, uniqueness: { scope: [ :source ] }
  validates :source, presence: true
end
