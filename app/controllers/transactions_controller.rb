class TransactionsController < ApplicationController
  include EntryableResource

  before_action :store_params!, only: :index

  def new
    super
    @income_categories = Current.family.categories.incomes.alphabetically
    @expense_categories = Current.family.categories.expenses.alphabetically
  end

  def index
    @q = search_params
    @search = Transaction::Search.new(Current.family, filters: @q)

    base_scope = @search.transactions_scope
                       .reverse_chronological
                       .includes(
                         { entry: :account },
                         :category, :merchant, :tags,
                         :transfer_as_inflow, :transfer_as_outflow
                       )

    @pagy, @transactions = pagy(base_scope, limit: per_page)

    # Load projected recurring transactions for next month
    @projected_recurring = Current.family.recurring_transactions
                                  .active
                                  .where("next_expected_date <= ? AND next_expected_date >= ?",
                                         1.month.from_now.to_date,
                                         Date.current)
                                  .includes(:merchant)
  end

  def clear_filter
    updated_params = {
      "q" => search_params,
      "page" => params[:page],
      "per_page" => params[:per_page]
    }

    q_params = updated_params["q"] || {}

    param_key = params[:param_key]
    param_value = params[:param_value]

    if q_params[param_key].is_a?(Array)
      q_params[param_key].delete(param_value)
      q_params.delete(param_key) if q_params[param_key].empty?
    else
      q_params.delete(param_key)
    end

    updated_params["q"] = q_params.presence

    # Add flag to indicate filters were explicitly cleared
    updated_params["filter_cleared"] = "1" if updated_params["q"].blank?

    Current.session.update!(prev_transaction_page_params: updated_params)

    redirect_to transactions_path(updated_params)
  end

  def create
    account = Current.family.accounts.find(params.dig(:entry, :account_id))
    requested_installments = params.dig(:entry, :installments_count).to_i
    installment_mode = params.dig(:entry, :installment_mode) || "divide"
    nature = params.dig(:entry, :nature)

    # Validate nature parameter
    unless [ "inflow", "outflow" ].include?(nature)
      @entry = account.entries.new(entry_params.except(:installments_count, :installment_mode))
      @entry.errors.add(:base, "Invalid transaction type")
      render :new, status: :unprocessable_entity and return
    end

    # Validate category matches transaction type (if category provided)
    category_id = params.dig(:entry, :entryable_attributes, :category_id)
    if category_id.present?
      category = Current.family.categories.find_by(id: category_id)
      if category
        expected_classification = nature == "inflow" ? "income" : "expense"
        if category.classification != expected_classification
          @entry = account.entries.new(entry_params.except(:installments_count, :installment_mode))
          @entry.errors.add(:base, "Category type does not match transaction type")
          @income_categories = Current.family.categories.incomes.alphabetically
          @expense_categories = Current.family.categories.expenses.alphabetically
          render :new, status: :unprocessable_entity and return
        end
      end
    end

    # Validate range 1..12
    if requested_installments < 1
      requested_installments = 1
    end

    if requested_installments > 12
      @entry = account.entries.new(entry_params.except(:installments_count, :installment_mode))
      @entry.errors.add(:installments_count, I18n.t("transactions.installments_range_error", min: 1, max: 12))
      render :new, status: :unprocessable_entity and return
    end

    installments = requested_installments

    if installments > 1
      base_params = entry_params.except(:installments_count, :installment_mode)
      amount = base_params[:amount].to_d

      created_entries = []

      begin
        group_id = SecureRandom.uuid

        ActiveRecord::Base.transaction do
          installments.times do |i|
            # Calculate installment amount based on mode
            if installment_mode == "replicate"
              # Replicate: use full amount for each installment
              inst_amount = amount
            else
              # Divide: distribute amount evenly using cents math
              sign = amount >= 0 ? 1 : -1
              cents = (amount.abs * 100).to_i
              quotient, remainder = cents.divmod(installments)
              inst_cents = quotient + (i < remainder ? 1 : 0)
              inst_amount = (inst_cents.to_d / 100) * sign
            end

            inst_params = base_params.deep_dup
            base_date = inst_params[:date].is_a?(String) ? Date.parse(inst_params[:date]) : inst_params[:date]
            inst_params[:date] = base_date + i.months
            base_name = inst_params[:name] || ""
            inst_params[:name] = "#{base_name} (#{i + 1}/#{installments})"
            inst_params[:amount] = inst_amount

            entry = account.entries.new(inst_params)
            entry.save!
            # Annotate transaction with installment metadata so they can be identified later
            transaction_record = entry.entryable
            if transaction_record.respond_to?(:extra)
              tx_extra = (transaction_record.extra || {}).deep_dup
              tx_extra["installment_group"] = group_id
              tx_extra["installment_index"] = i + 1
              tx_extra["installments_total"] = installments
              tx_extra["installment_mode"] = installment_mode
              transaction_record.update!(extra: tx_extra)
            end

            entry.sync_account_later
            created_entries << entry
          end
        end

        flash[:notice] = I18n.t("transactions.created_installments", count: installments)
        respond_to do |format|
          format.html { redirect_back_or_to account_path(created_entries.first.account) }
          format.turbo_stream { stream_redirect_back_or_to(account_path(created_entries.first.account)) }
        end
      rescue ActiveRecord::RecordInvalid => e
        @entry = account.entries.new(entry_params.except(:installments_count, :installment_mode))
        @entry.errors.add(:base, e.record.errors.full_messages.join(", "))
        render :new, status: :unprocessable_entity
      end

      return
    end

    @entry = account.entries.new(entry_params.except(:installments_count, :installment_mode))

    if @entry.save
      @entry.sync_account_later
      @entry.lock_saved_attributes!
      @entry.transaction.lock_attr!(:tag_ids) if @entry.transaction.tags.any?

      flash[:notice] = "Transaction created"

      respond_to do |format|
        format.html { redirect_back_or_to account_path(@entry.account) }
        format.turbo_stream { stream_redirect_back_or_to(account_path(@entry.account)) }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @entry.update(entry_params)
      transaction = @entry.transaction

      if needs_rule_notification?(transaction)
        flash[:cta] = {
          type: "category_rule",
          category_id: transaction.category_id,
          category_name: transaction.category.name
        }
      end

      @entry.sync_account_later
      @entry.lock_saved_attributes!
      @entry.transaction.lock_attr!(:tag_ids) if @entry.transaction.tags.any?

      respond_to do |format|
        format.html { redirect_back_or_to account_path(@entry.account), notice: "Transaction updated" }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              dom_id(@entry, :header),
              partial: "transactions/header",
              locals: { entry: @entry }
            ),
            turbo_stream.replace(@entry),
            *flash_notification_stream_items
          ]
        end
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  def merge_duplicate
    transaction = Current.family.transactions.includes(entry: :account).find(params[:id])

    if transaction.merge_with_duplicate!
      flash[:notice] = t("transactions.merge_duplicate.success")
    else
      flash[:alert] = t("transactions.merge_duplicate.failure")
    end

    redirect_to transactions_path
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordInvalid => e
    Rails.logger.error("Failed to merge duplicate transaction #{params[:id]}: #{e.message}")
    flash[:alert] = t("transactions.merge_duplicate.failure")
    redirect_to transactions_path
  end

  def dismiss_duplicate
    transaction = Current.family.transactions.includes(entry: :account).find(params[:id])

    if transaction.dismiss_duplicate_suggestion!
      flash[:notice] = t("transactions.dismiss_duplicate.success")
    else
      flash[:alert] = t("transactions.dismiss_duplicate.failure")
    end

    redirect_back_or_to transactions_path
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Failed to dismiss duplicate suggestion for transaction #{params[:id]}: #{e.message}")
    flash[:alert] = t("transactions.dismiss_duplicate.failure")
    redirect_back_or_to transactions_path
  end

  def mark_as_recurring
    transaction = Current.family.transactions.includes(entry: :account).find(params[:id])

    # Check if a recurring transaction already exists for this pattern
    existing = Current.family.recurring_transactions.find_by(
      merchant_id: transaction.merchant_id,
      name: transaction.merchant_id.present? ? nil : transaction.entry.name,
      currency: transaction.entry.currency,
      manual: true
    )

    if existing
      flash[:alert] = t("recurring_transactions.already_exists")
      redirect_back_or_to transactions_path
      return
    end

    begin
      recurring_transaction = RecurringTransaction.create_from_transaction(transaction)

      respond_to do |format|
        format.html do
          flash[:notice] = t("recurring_transactions.marked_as_recurring")
          redirect_back_or_to transactions_path
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_to do |format|
        format.html do
          flash[:alert] = t("recurring_transactions.creation_failed")
          redirect_back_or_to transactions_path
        end
      end
    rescue StandardError => e
      respond_to do |format|
        format.html do
          flash[:alert] = t("recurring_transactions.unexpected_error")
          redirect_back_or_to transactions_path
        end
      end
    end
  end

  def update_preferences
    Current.user.update_transactions_preferences(preferences_params)
    head :ok
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
    head :unprocessable_entity
  end

  private
    def per_page
      params[:per_page].to_i.positive? ? params[:per_page].to_i : 20
    end

    def needs_rule_notification?(transaction)
      return false if Current.user.rule_prompts_disabled

      if Current.user.rule_prompt_dismissed_at.present?
        time_since_last_rule_prompt = Time.current - Current.user.rule_prompt_dismissed_at
        return false if time_since_last_rule_prompt < 1.day
      end

      transaction.saved_change_to_category_id? && transaction.category_id.present? &&
      transaction.eligible_for_category_rule?
    end

    def entry_params
      entry_params = params.require(:entry).permit(
        :name, :date, :amount, :currency, :excluded, :notes, :nature, :entryable_type, :installments_count, :installment_mode,
        entryable_attributes: [ :id, :category_id, :merchant_id, :kind, :investment_activity_label, { tag_ids: [] } ]
      )

      nature = entry_params.delete(:nature)

      if nature.present? && entry_params[:amount].present?
        signed_amount = nature == "inflow" ? -entry_params[:amount].to_d : entry_params[:amount].to_d
        entry_params = entry_params.merge(amount: signed_amount)
      end

      entry_params
    end

    def search_params
      cleaned_params = params.fetch(:q, {})
              .permit(
                :start_date, :end_date, :search, :amount,
                :amount_operator, :active_accounts_only,
                accounts: [], account_ids: [],
                categories: [], merchants: [], types: [], tags: [], status: []
              )
              .to_h
              .compact_blank

      cleaned_params.delete(:amount_operator) unless cleaned_params[:amount].present?


      cleaned_params
    end

    def store_params!
      if should_restore_params?
        params_to_restore = {}

        params_to_restore[:q] = stored_params["q"].presence || {}
        params_to_restore[:page] = stored_params["page"].presence || 1
        params_to_restore[:per_page] = stored_params["per_page"].presence || 50

        redirect_to transactions_path(params_to_restore)
      else
        Current.session.update!(
          prev_transaction_page_params: {
            q: search_params,
            page: params[:page],
            per_page: params[:per_page]
          }
        )
      end
    end

    def should_restore_params?
      request.query_parameters.blank? && (stored_params["q"].present? || stored_params["page"].present? || stored_params["per_page"].present?)
    end

    def stored_params
      Current.session.prev_transaction_page_params
    end

    def preferences_params
      params.require(:preferences).permit(collapsed_sections: {})
    end
end
