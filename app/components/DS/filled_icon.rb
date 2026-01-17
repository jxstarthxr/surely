class DS::FilledIcon < DesignSystemComponent
  attr_reader :icon, :text, :hex_color, :size, :rounded, :variant

  VARIANTS = %i[default text surface container inverse].freeze

  SIZES = {
    sm: {
      container_size: "w-10 h-10",
      container_radius: "rounded-[22%]",
      border: "border-2",
      icon_size: "sm",
      text_size: "text-xs"
    },
    md: {
      container_size: "w-12 h-12",
      container_radius: "rounded-[22%]",
      border: "border-2",
      icon_size: "md",
      text_size: "text-sm"
    },
    lg: {
      container_size: "w-14 h-14",
      container_radius: "rounded-[22%]",
      border: "border-2",
      icon_size: "lg",
      text_size: "text-base"
    },
    xl: {
      container_size: "w-16 h-16",
      container_radius: "rounded-[22%]",
      border: "border-2",
      icon_size: "xl",
      text_size: "text-lg"
    }
  }.freeze

  def initialize(variant: :default, icon: nil, text: nil, hex_color: nil, size: "md", rounded: false)
    @variant = variant.to_sym
    @icon = icon
    @text = text
    @hex_color = hex_color
    @size = size.to_sym
    @rounded = rounded
  end

  def container_classes
    class_names(
      "flex justify-center items-center shrink-0",
      size_classes,
      radius_classes,
      border_classes,
      transparent? ? nil : solid_bg_class
    )
  end

  def icon_size
    SIZES[size][:icon_size]
  end

  def text_classes
    class_names(
      "text-center font-medium uppercase",
      SIZES[size][:text_size]
    )
  end

  def container_styles
    <<~STYLE.strip
      background-color: #{transparent_bg_color};
      border-color: #{transparent_border_color};
      color: #{custom_fg_color};
    STYLE
  end

  def transparent?
    variant.in?(%i[default text])
  end

  private
    def solid_bg_class
      case variant
      when :surface
        "bg-surface-inset"
      when :container
        "bg-container-inset"
      when :inverse
        "bg-container"
      end
    end

    def size_classes
      SIZES[size][:container_size]
    end

    def radius_classes
      rounded ? "rounded-full" : SIZES[size][:container_radius]
    end

    def border_classes
      SIZES[size][:border]
    end

    def custom_fg_color
      hex_color || "var(--color-gray-500)"
    end

    def transparent_bg_color
      "color-mix(in oklab, #{custom_fg_color} 10%, transparent)"
    end

    def transparent_border_color
      "color-mix(in oklab, #{custom_fg_color} 10%, transparent)"
    end
end
