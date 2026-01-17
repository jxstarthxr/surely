import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="account-form"
export default class extends Controller {
  static targets = ["logoPreview", "logoPlaceholder", "removeButton"]

  removeLogo(event) {
    event.preventDefault()

    // Clear the file input
    const fileInput = this.element.querySelector('input[type="file"][name*="logo"]')
    if (fileInput) {
      fileInput.value = ''
    }

    // Add a hidden field to mark logo for removal
    const existingRemovalField = this.element.querySelector('input[name*="remove_logo"]')
    if (!existingRemovalField) {
      const removalInput = document.createElement('input')
      removalInput.type = 'hidden'
      removalInput.name = 'account[remove_logo]'
      removalInput.value = '1'
      this.element.querySelector('form').appendChild(removalInput)
    }

    // Hide the logo preview and show placeholder
    if (this.hasLogoPreviewTarget) {
      this.logoPreviewTarget.classList.add('hidden')
    }

    if (this.hasLogoPlaceholderTarget) {
      this.logoPlaceholderTarget.classList.remove('hidden')
    }

    // Hide the remove button
    if (this.hasRemoveButtonTarget) {
      this.removeButtonTarget.classList.add('hidden')
    }

    // Update the upload button text
    const uploadLabel = this.element.querySelector('label[for="account_logo_upload"]')
    if (uploadLabel) {
      // Get the "upload_logo" translation (ideally this would come from data attribute)
      uploadLabel.textContent = uploadLabel.textContent.replace(/change/i, 'Upload')
    }
  }
}
