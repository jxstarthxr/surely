class FamilyMerchant < Merchant
  COLORS = %w[#e99537 #4da568 #6471eb #db5a54 #df4e92 #c44fe9 #eb5429 #61c9ea #805dee #6ad28a]

  belongs_to :family

  before_validation :set_default_color
  before_save :generate_logo_url_from_website, if: :should_generate_logo?
  before_save :clear_logo_url_if_website_blank

  validates :color, presence: true
  validates :name, uniqueness: { scope: :family }

  # Track if logo_url was explicitly set by the form (even if set to blank)
  # This prevents auto-generation when frontend validates the favicon
  attr_accessor :logo_url_explicitly_set

  # Override logo_url= to track when it's explicitly set
  def logo_url=(value)
    @logo_url_explicitly_set = true
    Rails.logger.debug "FamilyMerchant#logo_url= called with value: #{value.inspect}"
    super
    Rails.logger.debug "FamilyMerchant#logo_url after assignment: #{logo_url.inspect}"
  end

  private
    def set_default_color
      self.color = COLORS.sample
    end

    def should_generate_logo?
      # Only auto-generate if:
      # - Website URL changed
      # - Logo URL was NOT explicitly set by the form (frontend didn't handle favicon)
      # - No logo is attached
      result = website_url_changed? && !@logo_url_explicitly_set && !logo.attached?
      Rails.logger.debug "FamilyMerchant#should_generate_logo? = #{result} (website_url_changed?: #{website_url_changed?}, @logo_url_explicitly_set: #{@logo_url_explicitly_set.inspect}, logo.attached?: #{logo.attached?})"
      result
    end

    def clear_logo_url_if_website_blank
      # Clear logo_url if website is removed AND it wasn't explicitly set by form
      # (If explicitly set, the form is handling the logo_url)
      if website_url.blank? && logo_url.present? && !@logo_url_explicitly_set
        # Use write_attribute to bypass the setter and avoid setting @logo_url_explicitly_set
        write_attribute(:logo_url, nil)
      end
    end

    def generate_logo_url_from_website
      if website_url.present?
        # Try Brandfetch if client ID is configured
        if Setting.brand_fetch_client_id.present?
          domain = extract_domain(website_url)
          # Use write_attribute to bypass the setter and avoid setting @logo_url_explicitly_set
          write_attribute(:logo_url, "https://cdn.brandfetch.io/#{domain}/icon/fallback/lettermark/w/40/h/40?c=#{Setting.brand_fetch_client_id}")
        else
          # Fallback to Google Favicon Service (free, no API key needed)
          # Use write_attribute to bypass the setter and avoid setting @logo_url_explicitly_set
          write_attribute(:logo_url, FaviconFetcher.fetch_url(website_url, size: 128))
        end
      elsif website_url.blank?
        # Use write_attribute to bypass the setter and avoid setting @logo_url_explicitly_set
        write_attribute(:logo_url, nil)
      end
    end

    def extract_domain(url)
      original_url = url
      normalized_url = url.start_with?("http://", "https://") ? url : "https://#{url}"
      URI.parse(normalized_url).host&.sub(/\Awww\./, "")
    rescue URI::InvalidURIError
      original_url.sub(/\Awww\./, "")
    end
end
