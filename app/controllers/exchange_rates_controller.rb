class ExchangeRatesController < ApplicationController
  def show
    @from = params.fetch(:from, "USD")
    @to = params.fetch(:to, "MXN")
    @date = params.fetch(:date, Date.today)

    provider = Provider::Registry.for_concept(:exchange_rates).get_provider(:exchange_rate_host)
    response = provider.fetch_exchange_rate(from: @from, to: @to, date: @date)

    if response.success?
      @rate = response.data
    else
      flash.now[:error] = "Error fetching exchange rate: #{response.error.message}"
      @rate = nil
    end
  rescue Provider::Error => e
    flash.now[:error] = "Error fetching exchange rate: #{e.message}"
    @rate = nil
  end
end
