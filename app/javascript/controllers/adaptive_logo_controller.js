import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="adaptive-logo"
export default class extends Controller {
  static targets = ["image", "container"]

  connect() {
    if (this.hasImageTarget) {
      // Wait for image to load before analyzing
      if (this.imageTarget.complete) {
        this.analyzeImage()
      } else {
        this.imageTarget.addEventListener('load', () => this.analyzeImage())
      }
    }
  }

  analyzeImage() {
    const img = this.imageTarget

    // Create a canvas to analyze the image
    const canvas = document.createElement('canvas')
    const ctx = canvas.getContext('2d')

    // Set canvas size to image size
    canvas.width = img.naturalWidth || img.width
    canvas.height = img.naturalHeight || img.height

    // Draw image on canvas
    try {
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height)

      // Get image data
      const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height)
      const data = imageData.data

      // Find content bounds by detecting non-transparent pixels
      const bounds = this.findContentBounds(data, canvas.width, canvas.height)

      // Apply scaling to compensate for transparent padding
      if (bounds) {
        this.applyContentScaling(bounds, canvas.width, canvas.height)
      }

      // Calculate average brightness and color
      let totalBrightness = 0
      let totalR = 0, totalG = 0, totalB = 0
      let pixelCount = 0

      // Sample every few pixels for performance
      for (let i = 0; i < data.length; i += 16) { // Skip every 4 pixels (4 values per pixel)
        const r = data[i]
        const g = data[i + 1]
        const b = data[i + 2]
        const a = data[i + 3]

        // Skip fully transparent pixels
        if (a < 10) continue

        // Calculate perceived brightness (weighted formula)
        const brightness = (0.299 * r + 0.587 * g + 0.114 * b)

        totalBrightness += brightness
        totalR += r
        totalG += g
        totalB += b
        pixelCount++
      }

      if (pixelCount === 0) return

      const avgBrightness = totalBrightness / pixelCount
      const avgR = totalR / pixelCount
      const avgG = totalG / pixelCount
      const avgB = totalB / pixelCount

      // Determine if logo is light or dark
      const isDark = avgBrightness < 128

      // Calculate saturation
      const max = Math.max(avgR, avgG, avgB)
      const min = Math.min(avgR, avgG, avgB)
      const saturation = max === 0 ? 0 : (max - min) / max

      // Apply adaptive background
      this.applyAdaptiveBackground(isDark, saturation, avgR, avgG, avgB)

    } catch (e) {
      // If canvas fails (CORS, etc), use default background
      console.log('Could not analyze logo:', e.message)
    }
  }

  findContentBounds(data, width, height) {
    const alphaThreshold = 10 // Pixels with alpha > 10 are considered content

    let minX = width
    let minY = height
    let maxX = 0
    let maxY = 0
    let hasContent = false

    // Scan all pixels to find content boundaries
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const i = (y * width + x) * 4
        const alpha = data[i + 3]

        if (alpha > alphaThreshold) {
          hasContent = true
          minX = Math.min(minX, x)
          minY = Math.min(minY, y)
          maxX = Math.max(maxX, x)
          maxY = Math.max(maxY, y)
        }
      }
    }

    if (!hasContent) return null

    return {
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1
    }
  }

  applyContentScaling(bounds, imageWidth, imageHeight) {
    // Calculate how much of the image is actual content vs transparent padding
    const contentWidthRatio = bounds.width / imageWidth
    const contentHeightRatio = bounds.height / imageHeight

    // Use the smaller ratio to ensure content fits
    const contentRatio = Math.min(contentWidthRatio, contentHeightRatio)

    // Only apply scaling if there's significant transparent padding (content uses less than 85% of space)
    if (contentRatio < 0.85) {
      // Scale up to compensate for padding, but cap at 1.4x to avoid over-scaling
      const scale = Math.min(1 / contentRatio, 1.4)

      // Apply the scale transform
      this.imageTarget.style.transform = `scale(${scale})`
    }
  }

  applyAdaptiveBackground(isDark, saturation, r, g, b) {
    if (!this.hasContainerTarget) return

    const container = this.containerTarget

    // Check if user prefers dark mode
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches

    let background, borderColor

    if (isDark) {
      // Dark logo - needs light background
      if (prefersDark) {
        // In dark mode, use brighter background for dark logos to ensure visibility
        background = 'linear-gradient(135deg, rgba(255,255,255,0.22) 0%, rgba(255,255,255,0.18) 100%)'
        // Border should contrast with dark theme background
        borderColor = 'rgba(255,255,255,0.4)'
      } else {
        // In light mode, use white/light gray background
        background = 'linear-gradient(135deg, rgba(255,255,255,0.95) 0%, rgba(245,245,245,0.95) 100%)'
        // Border should contrast with light theme background
        borderColor = 'rgba(0,0,0,0.2)'
      }
    } else {
      // Light logo - needs dark background
      if (prefersDark) {
        // In dark mode, use darker background for light logos
        background = 'linear-gradient(135deg, rgba(0,0,0,0.35) 0%, rgba(0,0,0,0.45) 100%)'
        // Border should contrast with dark theme background
        borderColor = 'rgba(255,255,255,0.35)'
      } else {
        // In light mode, use dark gray background for light logos
        background = 'linear-gradient(135deg, rgba(0,0,0,0.15) 0%, rgba(0,0,0,0.22) 100%)'
        // Border should contrast with light theme background
        borderColor = 'rgba(0,0,0,0.2)'
      }
    }

    // Apply styles
    container.style.background = background
    container.style.borderColor = borderColor

    // Add a subtle transition for theme changes
    container.style.transition = 'background 0.3s ease, border-color 0.3s ease'
  }
}
