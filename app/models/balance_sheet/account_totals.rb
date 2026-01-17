class BalanceSheet::AccountTotals
  def initialize(family, sync_status_monitor:)
    @family = family
    @sync_status_monitor = sync_status_monitor
  end

  def asset_accounts
    @asset_accounts ||= account_rows.filter { |t| t.classification == "asset" }
  end

  def liability_accounts
    @liability_accounts ||= account_rows.filter { |t| t.classification == "liability" }
  end

  private
    attr_reader :family, :sync_status_monitor

    AccountRow = Data.define(:account, :converted_balance, :is_syncing) do
      def syncing? = is_syncing

      # Allows Rails path helpers to generate URLs from the wrapper
      def to_param = account.to_param
      delegate_missing_to :account
    end

    def visible_accounts
      @visible_accounts ||= family.accounts.visible.with_attached_logo
    end

    def account_rows
      @account_rows ||= query.map do |account_row|
        # Use balance_including_future for liabilities to show total debt obligation
        balance_to_use = account_row.liability? ? account_row.balance_including_future : account_row.balance

        # Convert to family currency if needed
        converted = if account_row.currency == family.currency
          balance_to_use
        else
          rate = ExchangeRate.find_rate(
            from: account_row.currency,
            to: family.currency,
            date: Date.current
          )
          balance_to_use * (rate || 1)
        end

        AccountRow.new(
          account: account_row,
          converted_balance: converted,
          is_syncing: sync_status_monitor.account_syncing?(account_row)
        )
      end
    end

    def cache_key
      family.build_cache_key(
        "balance_sheet_account_rows",
        invalidate_on_data_updates: true
      )
    end

    def query
      @query ||= Rails.cache.fetch(cache_key) do
        visible_accounts.to_a
      end
    end
end
