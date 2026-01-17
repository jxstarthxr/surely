class AddDeferredToNextCycleToTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :transactions, :deferred_to_next_cycle, :boolean, default: false, comment: "Manually deferred to next billing cycle"
    add_index :transactions, :deferred_to_next_cycle
  end
end
