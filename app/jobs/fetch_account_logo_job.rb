class FetchAccountLogoJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account
    return if account.institution_domain.blank?

    # Check if logo is manually uploaded (doesn't end with "_logo.png")
    has_manual_logo = account.logo.attached? &&
                      account.logo.filename.to_s.present? &&
                      !account.logo.filename.to_s.end_with?("_logo.png")

    # Don't replace manually uploaded logos
    if has_manual_logo
      Rails.logger.info("Skipping logo fetch for account #{account_id} - manual logo present")
      return
    end

    # Purge existing auto-fetched logo if present (will be replaced with new favicon)
    account.logo.purge if account.logo.attached?

    Rails.logger.info("Fetching logo for account #{account_id} from #{account.institution_domain}")
    # Fetch and attach the favicon (fetched at 256px but usually returns ~48x48)
    FaviconFetcher.attach_to(
      account.institution_domain,
      attachable: account,
      attachment_name: :logo
    )
  rescue StandardError => e
    Rails.logger.error("Failed to fetch logo for account #{account_id}: #{e.message}")
  end
end
