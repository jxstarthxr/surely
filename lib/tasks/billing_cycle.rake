namespace :billing_cycle do
  desc "Backfill billing cycle data for existing transactions"
  task backfill: :environment do
    puts "Starting billing cycle backfill for existing transactions..."

    # Find all credit card transactions that don't have billing cycle locked yet
    transactions_to_lock = Transaction.joins(entry: :account)
      .where(accounts: { accountable_type: "CreditCard" })
      .where(billing_cycle_month: nil)
      .includes(entry: :account)

    total_count = transactions_to_lock.count
    puts "Found #{total_count} transactions to process"

    locked_count = 0
    skipped_count = 0

    transactions_to_lock.find_each.with_index do |transaction, index|
      credit_card = transaction.entry.account.accountable

      if credit_card.due_day.present?
        transaction.lock_billing_cycle!
        locked_count += 1
      else
        skipped_count += 1
      end

      # Progress indicator every 100 transactions
      if (index + 1) % 100 == 0
        puts "Processed #{index + 1}/#{total_count} transactions..."
      end
    end

    puts "\nBackfill complete!"
    puts "Locked: #{locked_count} transactions"
    puts "Skipped: #{skipped_count} transactions (no billing cycle configured)"
  end
end
