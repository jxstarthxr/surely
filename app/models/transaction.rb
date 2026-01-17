class Transaction < ApplicationRecord
  include Entryable, Transferable, Ruleable

  belongs_to :category, optional: true
  belongs_to :merchant, optional: true

  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings

  accepts_nested_attributes_for :taggings, allow_destroy: true

  after_save :clear_merchant_unlinked_association, if: :merchant_id_previously_changed?
  after_save :recalculate_billing_cycle!, if: :should_recalculate_billing_cycle?

  enum :kind, {
    standard: "standard", # A regular transaction, included in budget analytics
    funds_movement: "funds_movement", # Movement of funds between accounts, excluded from budget analytics
    cc_payment: "cc_payment", # A CC payment, excluded from budget analytics (CC payments offset the sum of expense transactions)
    loan_payment: "loan_payment", # A payment to a Loan account, treated as an expense in budgets
    one_time: "one_time", # A one-time expense/income, excluded from budget analytics
    investment_contribution: "investment_contribution" # Transfer to investment/crypto account, excluded from budget analytics
  }

  # All valid investment activity labels (for UI dropdown)
  ACTIVITY_LABELS = [
    "Buy", "Sell", "Sweep In", "Sweep Out", "Dividend", "Reinvestment",
    "Interest", "Fee", "Transfer", "Contribution", "Withdrawal", "Exchange", "Other"
  ].freeze

  # Pending transaction scopes - filter based on provider pending flags in extra JSONB
  # Works with any provider that stores pending status in extra["provider_name"]["pending"]
  scope :pending, -> {
    where(<<~SQL.squish)
      (transactions.extra -> 'simplefin' ->> 'pending')::boolean = true
      OR (transactions.extra -> 'plaid' ->> 'pending')::boolean = true
    SQL
  }

  scope :excluding_pending, -> {
    where(<<~SQL.squish)
      (transactions.extra -> 'simplefin' ->> 'pending')::boolean IS DISTINCT FROM true
      AND (transactions.extra -> 'plaid' ->> 'pending')::boolean IS DISTINCT FROM true
    SQL
  }

  # Overarching grouping method for all transfer-type transactions
  def transfer?
    funds_movement? || cc_payment? || loan_payment?
  end

  def set_category!(category)
    if category.is_a?(String)
      category = entry.account.family.categories.find_or_create_by!(
        name: category
      )
    end

    update!(category: category)
  end

  def pending?
    extra_data = extra.is_a?(Hash) ? extra : {}
    ActiveModel::Type::Boolean.new.cast(extra_data.dig("simplefin", "pending")) ||
      ActiveModel::Type::Boolean.new.cast(extra_data.dig("plaid", "pending"))
  rescue
    false
  end

  # Check if transaction is deferred to next billing cycle
  # This includes both manual deferral and automatic deferral based on cutoff date
  def deferred_to_next_billing_cycle?
    return false unless entry&.account&.accountable.is_a?(CreditCard)

    # Manual deferral takes precedence
    return true if deferred_to_next_cycle?

    credit_card = entry.account.accountable
    return false unless credit_card.due_day.present?

    # If we have a locked billing cycle month, use that to determine if deferred
    if billing_cycle_month.present?
      # Transaction is deferred if payment month is in a later month than transaction month
      # Same month = current cycle (no badge), later month = next cycle or beyond (show badge)
      # Compare year and month only to avoid any time-of-day issues
      transaction_year = entry.date.year
      transaction_month = entry.date.month
      payment_year = billing_cycle_month.year
      payment_month = billing_cycle_month.month

      # Compare: payment is deferred if it's in a later year, or same year but later month
      return (payment_year > transaction_year) ||
             (payment_year == transaction_year && payment_month > transaction_month)
    end

    # If billing cycle is not locked, don't show the badge for old transactions
    # to avoid confusion when credit card settings change
    false
  end

  # Get the actual payment due date for this transaction
  # considering billing cycles
  def payment_due_date
    return entry.date unless entry&.account&.accountable.is_a?(CreditCard)

    credit_card = entry.account.accountable
    return entry.date unless credit_card.due_day.present?

    # If we have a locked billing cycle month, use that
    # This ensures changes to credit card billing settings don't affect old transactions
    if billing_cycle_month.present?
      return Date.new(
        billing_cycle_month.year,
        billing_cycle_month.month,
        [credit_card.due_day, Date.new(billing_cycle_month.year, billing_cycle_month.month, -1).day].min
      )
    end

    # Otherwise calculate dynamically (for backward compatibility with old transactions)
    # Find which billing cycle this transaction belongs to
    if deferred_to_next_cycle?
      # Manually deferred - goes to next month's bill
      credit_card.payment_due_date_for_month(entry.date.next_month)
    elsif credit_card.transaction_in_next_cycle?(entry.date, entry.date)
      # Past cutoff - automatically goes to next month
      credit_card.payment_due_date_for_month(entry.date.next_month)
    else
      # Within current cycle
      credit_card.payment_due_date_for_month(entry.date)
    end
  end

  # Potential duplicate matching methods
  # These help users review and resolve fuzzy-matched pending/posted pairs

  def has_potential_duplicate?
    potential_posted_match_data.present? && !potential_duplicate_dismissed?
  end

  def potential_duplicate_entry
    return nil unless has_potential_duplicate?
    Entry.find_by(id: potential_posted_match_data["entry_id"])
  end

  def potential_duplicate_reason
    potential_posted_match_data&.dig("reason")
  end

  def potential_duplicate_confidence
    potential_posted_match_data&.dig("confidence") || "medium"
  end

  def low_confidence_duplicate?
    potential_duplicate_confidence == "low"
  end

  def potential_duplicate_posted_amount
    potential_posted_match_data&.dig("posted_amount")&.to_d
  end

  def potential_duplicate_dismissed?
    potential_posted_match_data&.dig("dismissed") == true
  end

  # Merge this pending transaction with its suggested posted match
  # This DELETES the pending entry since the posted version is canonical
  def merge_with_duplicate!
    return false unless has_potential_duplicate?

    posted_entry = potential_duplicate_entry
    return false unless posted_entry

    pending_entry_id = entry.id
    pending_entry_name = entry.name

    # Delete this pending entry completely (no need to keep it around)
    entry.destroy!

    Rails.logger.info("User merged pending entry #{pending_entry_id} (#{pending_entry_name}) with posted entry #{posted_entry.id}")
    true
  end

  # Dismiss the duplicate suggestion - user says these are NOT the same transaction
  def dismiss_duplicate_suggestion!
    return false unless potential_posted_match_data.present?

    updated_extra = (extra || {}).deep_dup
    updated_extra["potential_posted_match"]["dismissed"] = true
    update!(extra: updated_extra)

    Rails.logger.info("User dismissed duplicate suggestion for entry #{entry.id}")
    true
  end

  # Clear the duplicate suggestion entirely
  def clear_duplicate_suggestion!
    return false unless potential_posted_match_data.present?

    updated_extra = (extra || {}).deep_dup
    updated_extra.delete("potential_posted_match")
    update!(extra: updated_extra)
    true
  end

  # Lock the billing cycle calculation for this transaction
  # This ensures changes to credit card billing settings don't retroactively affect this transaction
  def lock_billing_cycle!
    return unless entry&.account&.accountable.is_a?(CreditCard)

    credit_card = entry.account.accountable
    return unless credit_card.due_day.present?

    # Calculate which month this transaction's payment is due
    payment_date = calculate_payment_due_date
    return unless payment_date

    # Store the month (not the full date) and timestamp when locked
    update_columns(
      billing_cycle_month: payment_date.beginning_of_month,
      billing_cycle_locked_at: Time.current
    )
  end

  # Recalculate and relock the billing cycle (e.g., when manual deferral changes)
  def recalculate_billing_cycle!
    return unless entry&.account&.accountable.is_a?(CreditCard)

    credit_card = entry.account.accountable
    return unless credit_card.due_day.present?

    payment_date = calculate_payment_due_date
    return unless payment_date

    update_columns(
      billing_cycle_month: payment_date.beginning_of_month,
      billing_cycle_locked_at: Time.current
    )
  end

  private

    # Calculate the payment due date based on current settings
    # This is used when locking the billing cycle
    def calculate_payment_due_date
      return nil unless entry&.account&.accountable.is_a?(CreditCard)

      credit_card = entry.account.accountable
      return nil unless credit_card.due_day.present?

      # Find which billing cycle this transaction belongs to
      if deferred_to_next_cycle?
        # Manually deferred - goes to next month's bill
        credit_card.payment_due_date_for_month(entry.date.next_month)
      elsif credit_card.transaction_in_next_cycle?(entry.date, entry.date)
        # Past cutoff - automatically goes to next month
        credit_card.payment_due_date_for_month(entry.date.next_month)
      else
        # Within current cycle
        credit_card.payment_due_date_for_month(entry.date)
      end
    end

    # Determine if billing cycle should be recalculated
    # This happens when the manual deferral flag changes
    def should_recalculate_billing_cycle?
      saved_change_to_deferred_to_next_cycle? && !new_record?
    end

    def potential_posted_match_data
      return nil unless extra.is_a?(Hash)
      extra["potential_posted_match"]
    end

    def clear_merchant_unlinked_association
      return unless merchant_id.present? && merchant.is_a?(ProviderMerchant)

      family = entry&.account&.family
      return unless family

      FamilyMerchantAssociation.where(family: family, merchant: merchant).delete_all
    end
end
