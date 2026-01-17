class AddBillingCycleInfoToTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :transactions, :billing_cycle_month, :date, comment: "The month when this transaction's payment is due (locked at creation)"
    add_column :transactions, :billing_cycle_locked_at, :datetime, comment: "When the billing cycle month was calculated and locked"
    add_index :transactions, :billing_cycle_month
  end
end
