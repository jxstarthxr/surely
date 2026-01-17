class FetchAccountLogoJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account
    return if account.logo.attached? || account.institution_domain.blank?

    # Fetch and attach the favicon
    FaviconFetcher.attach_to(
      account.institution_domain,
      attachable: account,
      attachment_name: :logo
    )
  rescue StandardError => e
    Rails.logger.error("Failed to fetch logo for account #{account_id}: #{e.message}")
  end
end
