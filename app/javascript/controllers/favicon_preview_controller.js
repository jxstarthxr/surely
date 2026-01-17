import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="favicon-preview"
export default class extends Controller {
  static targets = ["input", "preview", "placeholder", "warning", "existingLogo"]
  static values = {
    size: { type: Number, default: 128 }
  }

  connect() {
    this.debouncedFetch = this.debounce(this.fetchFavicon.bind(this), 500)

    // On page load, validate existing favicon if input has a value
    if (this.hasInputTarget && this.inputTarget.value.trim().length > 0) {
      this.validateExistingFavicon()
    }

    // Logo will be fetched server-side after save based on institution_domain
  }

  validateExistingFavicon() {
    const value = this.inputTarget.value.trim()
    const domain = this.extractDomain(value)

    if (!domain) return

    // Build Google Favicon Service URL
    const faviconUrl = `https://www.google.com/s2/favicons?domain=${domain}&sz=${this.sizeValue}`

    // Test if the existing favicon is valid
    const testImg = new Image()

    testImg.onload = () => {
      const width = testImg.naturalWidth
      const height = testImg.naturalHeight

      if (width < 32 || height < 32) {
        // Invalid favicon - show warning
        this.handleError()
      }
      // If valid, do nothing (keep showing the existing logo)
    }

    testImg.onerror = () => {
      // Invalid favicon - show warning
      this.handleError()
    }

    testImg.src = faviconUrl
  }

  handleError() {
    // Show warning when favicon fails to load
    if (this.hasWarningTarget) {
      this.warningTarget.classList.remove('hidden')
    }

    // Mark logo for removal by adding hidden field
    this.markLogoForRemoval()

    this.showPlaceholder()
  }

  markLogoForRemoval() {
    // Add a hidden field to mark logo for removal (same as remove button does)
    const form = this.element.querySelector('form')
    if (!form) return

    const existingRemovalField = form.querySelector('input[name*="remove_logo"]')
    if (!existingRemovalField) {
      const removalInput = document.createElement('input')
      removalInput.type = 'hidden'
      removalInput.name = 'account[remove_logo]'
      removalInput.value = '1'
      form.appendChild(removalInput)
    }
  }

  // Called when user types in the URL/domain field
  handleInput() {
    const value = this.inputTarget.value.trim()

    // Hide warning when user starts typing again
    if (this.hasWarningTarget) {
      this.warningTarget.classList.add('hidden')
    }

    if (value.length === 0) {
      // Domain field is empty, mark logo for removal
      this.markLogoForRemoval()
      this.showPlaceholder()
      this.hideExistingLogo()
      return
    }

    // Remove the logo removal flag when user types a new domain
    // (logo will only be removed if the new domain fails validation)
    this.clearLogoRemovalFlag()
    this.showExistingLogo()

    // Debounced fetch
    this.debouncedFetch(value)
  }

  clearLogoRemovalFlag() {
    const form = this.element.querySelector('form')
    if (!form) return

    const existingRemovalField = form.querySelector('input[name*="remove_logo"]')
    if (existingRemovalField) {
      existingRemovalField.remove()
    }
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

    // Get the parent container that has the background styling
    const previewContainer = this.previewTarget.closest('[style*="background"]')

    if (this.previewTarget.tagName === 'IMG') {
      this.previewTarget.src = faviconUrl

      // Make the container visible if it was hidden
      if (previewContainer) {
        previewContainer.classList.remove('opacity-0')
        previewContainer.style.transition = 'opacity 0.2s ease-in-out'
        previewContainer.style.opacity = '1'
      }

      this.previewTarget.style.transition = 'opacity 0.2s ease-in-out'
      this.previewTarget.style.opacity = '1'
      // Remove any opacity classes that might be set
      this.previewTarget.classList.remove('opacity-0')

      // Trigger adaptive logo analysis when image loads
      this.previewTarget.addEventListener('load', () => {
        const adaptiveLogoController = this.application.getControllerForElementAndIdentifier(
          previewContainer,
          'adaptive-logo'
        )
        if (adaptiveLogoController) {
          adaptiveLogoController.analyzeImage()
        }
      }, { once: true })
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
      this.placeholderTarget.style.opacity = '1'
    }
    if (this.hasPreviewTarget && this.previewTarget.tagName === 'IMG') {
      this.previewTarget.style.opacity = '0'
      this.previewTarget.classList.add('opacity-0')
      // Clear the src to prevent showing broken/placeholder images
      this.previewTarget.src = ''
    }
    // Don't clear the hidden field - keep the existing logo_url if it was valid before
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

  hideExistingLogo() {
    if (this.hasExistingLogoTarget) {
      this.existingLogoTarget.style.transition = 'opacity 0.2s ease-in-out'
      this.existingLogoTarget.style.opacity = '0'
      setTimeout(() => {
        this.existingLogoTarget.classList.add('hidden')
      }, 200)
    }
  }

  showExistingLogo() {
    if (this.hasExistingLogoTarget) {
      this.existingLogoTarget.classList.remove('hidden')
      this.existingLogoTarget.style.transition = 'opacity 0.2s ease-in-out'
      this.existingLogoTarget.style.opacity = '1'
    }
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
