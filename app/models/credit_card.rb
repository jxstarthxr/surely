class CreditCard < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "credit_card" => { short: "Credit Card", long: "Credit Card" }
  }.freeze

  validates :due_day, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 31, allow_nil: true }
  validates :cutoff_days_before_due, numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_nil: true }

  class << self
    def color
      "#F13636"
    end

    def icon
      "credit-card"
    end

    def classification
      "liability"
    end
  end

  def available_credit_money
    available_credit ? Money.new(available_credit, account.currency) : nil
  end

  def minimum_payment_money
    minimum_payment ? Money.new(minimum_payment, account.currency) : nil
  end

  def annual_fee_money
    annual_fee ? Money.new(annual_fee, account.currency) : nil
  end

  # Calculate the cutoff date for a given month
  # Transactions on or after this date will be included in next month's bill
  def cutoff_date_for_month(date)
    return nil unless due_day.present?

    target_date = Date.new(date.year, date.month, [due_day, Date.new(date.year, date.month, -1).day].min)

    if cutoff_days_before_due.present? && cutoff_days_before_due > 0
      target_date - cutoff_days_before_due.days
    else
      target_date
    end
  end

  # Calculate the payment due date for transactions in a given month
  # Returns the due date when this month's charges will be paid
  def payment_due_date_for_month(date)
    return nil unless due_day.present?

    # Start with the cutoff date for this month
    cutoff = cutoff_date_for_month(date)
    return nil unless cutoff

    # The payment is due on the next due_day after the cutoff
    # If cutoff is on the 10th and due_day is 15th, payment is due on the 15th of the same month
    # If cutoff is on the 25th and due_day is 15th, payment is due on the 15th of the next month

    due_in_same_month = Date.new(date.year, date.month, [due_day, Date.new(date.year, date.month, -1).day].min)

    if cutoff <= due_in_same_month
      due_in_same_month
    else
      # Due date is in next month
      next_month = date.next_month
      Date.new(next_month.year, next_month.month, [due_day, Date.new(next_month.year, next_month.month, -1).day].min)
    end
  end

  # Determine if a transaction falls into the current billing cycle or the next one
  # based on the cutoff date
  def transaction_in_next_cycle?(transaction_date, reference_date = Date.current)
    return false unless due_day.present?

    cutoff = cutoff_date_for_month(reference_date)
    return false unless cutoff

    transaction_date >= cutoff
  end

  # Get the billing cycle period for a given payment due date
  # Returns [start_date, end_date] of the billing cycle
  def billing_cycle_for_due_date(due_date)
    return nil unless due_day.present?

    # Work backwards from the due date
    cutoff = due_date
    if cutoff_days_before_due.present? && cutoff_days_before_due > 0
      cutoff = due_date + cutoff_days_before_due.days
    end

    # The cycle starts the day after the previous cycle's cutoff
    previous_month_cutoff = cutoff_date_for_month(due_date - 1.month)

    if previous_month_cutoff
      [previous_month_cutoff, cutoff - 1.day]
    else
      [due_date.beginning_of_month, cutoff - 1.day]
    end
  end
end
