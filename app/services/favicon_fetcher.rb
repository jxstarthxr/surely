# Service to fetch high-quality favicons from websites
# Uses Google's favicon service as a reliable source
class FaviconFetcher
  GOOGLE_FAVICON_URL = "https://www.google.com/s2/favicons"

  # Fetch favicon for a given domain or URL
  # @param url_or_domain [String] Full URL (https://example.com) or domain (example.com)
  # @param size [Integer] Icon size (16, 32, 64, 128, 256)
  # @return [String, nil] URL to the favicon or nil if invalid
  def self.fetch_url(url_or_domain, size: 128)
    return nil if url_or_domain.blank?

    # Extract domain from URL if full URL is provided
    domain = extract_domain(url_or_domain)
    return nil if domain.blank?

    # Build Google Favicon Service URL with requested size
    "#{GOOGLE_FAVICON_URL}?domain=#{domain}&sz=#{size}"
  end

  # Download and attach favicon to an ActiveStorage attachment
  # @param url_or_domain [String] Full URL or domain
  # @param attachable [ActiveRecord::Base] Model with has_one_attached
  # @param attachment_name [Symbol] Name of the attachment (e.g., :logo)
  # @return [Boolean] true if successfully attached, false otherwise
  def self.attach_to(url_or_domain, attachable:, attachment_name: :logo)
    return false if url_or_domain.blank?

    favicon_url = fetch_url(url_or_domain, size: 256)
    return false if favicon_url.blank?

    begin
      # Download the favicon
      uri = URI.parse(favicon_url)
      response = Net::HTTP.get_response(uri)

      return false unless response.is_a?(Net::HTTPSuccess)

      # Attach to the model
      filename = "#{extract_domain(url_or_domain)}_logo.png"
      attachable.public_send(attachment_name).attach(
        io: StringIO.new(response.body),
        filename: filename,
        content_type: "image/png"
      )

      true
    rescue StandardError => e
      Rails.logger.error("Failed to fetch favicon for #{url_or_domain}: #{e.message}")
      false
    end
  end

  private

  # Extract domain from URL or return as-is if already a domain
  # @param url_or_domain [String]
  # @return [String, nil]
  def self.extract_domain(url_or_domain)
    return nil if url_or_domain.blank?

    # Remove protocol if present
    domain = url_or_domain.sub(/\Ahttps?:\/\//, "")

    # Remove www. prefix
    domain = domain.sub(/\Awww\./, "")

    # Remove path, query, and fragment
    domain = domain.split("/").first
    domain = domain.split("?").first
    domain = domain.split("#").first

    # Remove port if present
    domain = domain.split(":").first

    domain.strip.downcase
  end
end
