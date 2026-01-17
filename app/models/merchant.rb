class Merchant < ApplicationRecord
  TYPES = %w[FamilyMerchant ProviderMerchant].freeze

  has_many :transactions, dependent: :nullify
  has_many :recurring_transactions, dependent: :destroy

  has_one_attached :logo do |attachable|
    attachable.variant :thumb, resize_to_limit: [128, 128], preprocessed: true
  end

  before_save :purge_old_logo, if: :logo_attached_changed?

  validates :name, presence: true
  validates :type, inclusion: { in: TYPES }

  scope :alphabetically, -> { order(:name) }

  # Get the logo URL - either from ActiveStorage attachment or logo_url field
  def logo_image_url(variant: :thumb)
    if logo.attached?
      if variant && logo.variable?
        Rails.application.routes.url_helpers.rails_representation_url(logo.variant(variant), only_path: true)
      else
        Rails.application.routes.url_helpers.rails_blob_path(logo, only_path: true)
      end
    elsif logo_url.present?
      logo_url
    end
  end

  private

  def logo_attached_changed?
    logo.attached? && logo_previously_changed?
  end

  def purge_old_logo
    # Purge old logo if a new one is being attached
    logo.purge_later if logo.attached? && logo_previously_changed?
  end
end
