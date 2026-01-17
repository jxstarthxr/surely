import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="favicon-preview"
export default class extends Controller {
  static targets = ["input", "preview", "placeholder", "warning"]
  static values = {
    size: { type: Number, default: 128 }
  }

  connect() {
    this.debouncedFetch = this.debounce(this.fetchFavicon.bind(this), 500)
  }

  handleError() {
    // Show warning when favicon fails to load
    if (this.hasWarningTarget) {
      this.warningTarget.classList.remove('hidden')
    }
    this.showPlaceholder()
  }

  // Called when user types in the URL/domain field
  handleInput() {
    const value = this.inputTarget.value.trim()

    // Hide warning when user starts typing again
    if (this.hasWarningTarget) {
      this.warningTarget.classList.add('hidden')
    }

    if (value.length === 0) {
      this.showPlaceholder()
      return
    }

    // Debounced fetch
    this.debouncedFetch(value)
  }

  async fetchFavicon(urlOrDomain) {
    const domain = this.extractDomain(urlOrDomain)

    if (!domain) {
      this.showPlaceholder()
      return
    }

    // Build Google Favicon Service URL
    const faviconUrl = `https://www.google.com/s2/favicons?domain=${domain}&sz=${this.sizeValue}`

    // Create a temporary image to test loading before updating the UI
    const testImg = new Image()

    testImg.onload = () => {
      // Check if it's the default icon before showing it
      const width = testImg.naturalWidth
      const height = testImg.naturalHeight

      if (width < 32 || height < 32) {
        // It's the default icon, show error
        this.handleError()
      } else {
        // Valid favicon, update the UI
        this.showFavicon(faviconUrl)
      }
    }

    testImg.onerror = () => {
      this.handleError()
    }

    // Start loading the test image
    testImg.src = faviconUrl
  }

  showFavicon(faviconUrl) {
    if (!this.hasPreviewTarget) return

    if (this.previewTarget.tagName === 'IMG') {
      this.previewTarget.src = faviconUrl
      this.previewTarget.style.transition = 'opacity 0.2s ease-in-out'
      this.previewTarget.style.opacity = '1'
    } else {
      // If preview is a div, replace with img
      const img = document.createElement('img')
      img.src = faviconUrl
      img.className = this.previewTarget.className
      img.alt = 'Logo preview'
      img.style.transition = 'opacity 0.2s ease-in-out'
      this.previewTarget.replaceWith(img)
    }

    // Fade out placeholder with animation
    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.style.transition = 'opacity 0.2s ease-in-out'
      this.placeholderTarget.style.opacity = '0'

      // Hide placeholder after fade completes
      setTimeout(() => {
        this.placeholderTarget.classList.add('hidden')
        this.placeholderTarget.style.opacity = '1' // Reset for next time
      }, 200)
    }
  }

  showPlaceholder() {
    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.classList.remove('hidden')
    }
    if (this.hasPreviewTarget && this.previewTarget.tagName === 'IMG') {
      this.previewTarget.style.opacity = '0'
    }
  }

  extractDomain(urlOrDomain) {
    if (!urlOrDomain) return null

    // Remove protocol if present
    let domain = urlOrDomain.replace(/^https?:\/\//, '')

    // Remove www. prefix
    domain = domain.replace(/^www\./, '')

    // Remove path, query, and fragment
    domain = domain.split('/')[0]
    domain = domain.split('?')[0]
    domain = domain.split('#')[0]

    // Remove port if present
    domain = domain.split(':')[0]

    return domain.trim().toLowerCase()
  }

  debounce(func, wait) {
    let timeout
    return function executedFunction(...args) {
      const later = () => {
        clearTimeout(timeout)
        func(...args)
      }
      clearTimeout(timeout)
      timeout = setTimeout(later, wait)
    }
  }
}
