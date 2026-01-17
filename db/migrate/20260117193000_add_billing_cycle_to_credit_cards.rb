class AddBillingCycleToCreditCards < ActiveRecord::Migration[7.2]
  def change
    add_column :credit_cards, :due_day, :integer, comment: "Day of month (1-31) when payment is due"
    add_column :credit_cards, :cutoff_days_before_due, :integer, default: 0, comment: "Days before due date that charges roll to next month's bill"
  end
end
