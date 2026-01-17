class ChangeDefaultPeriodToLastMonth < ActiveRecord::Migration[7.2]
  def up
    # Change the default value for the column
    change_column_default :users, :default_period, from: "last_30_days", to: "last_month"

    # Update existing users who have the old default to the new default
    User.where(default_period: "last_30_days").update_all(default_period: "last_month")
  end

  def down
    # Revert the default value
    change_column_default :users, :default_period, from: "last_month", to: "last_30_days"

    # Revert existing users back to old default
    User.where(default_period: "last_month").update_all(default_period: "last_30_days")
  end
end
