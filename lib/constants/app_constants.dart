/// Application-wide constants for configuration and magic numbers
/// This file centralizes all hardcoded values to improve maintainability
class AppConstants {
  // Private constructor to prevent instantiation
  AppConstants._();

  // ==================== GPS & Location ====================

  /// Minimum distance in meters before GPS auto-centering triggers
  /// Prevents excessive map movements for minor GPS drift
  static const double gpsAutoCenterThreshold = 50.0;

  /// Default zoom level when centering on user location
  static const double defaultGpsZoom = 15.0;

  /// Zoom level for search result navigation
  static const double searchResultZoom = 16.0;

  /// Map debounce delay in milliseconds to prevent excessive reloads
  static const int mapDebounceDelayMs = 1000;

  /// Search debounce delay in seconds
  static const int searchDebounceDelaySec = 2;

  // ==================== Map Bounds & Loading ====================

  /// Multiplier for extended bounds loading area
  /// Value of 1.0 means load an area 3x3 times the visible map
  static const double boundsExtensionMultiplier = 1.0;

  /// Buffer zone percentage for reload trigger (0.1 = 10%)
  /// When user moves within this buffer, data reload is triggered
  static const double reloadTriggerBufferPercent = 0.1;

  /// Minimum and maximum zoom levels for the map
  static const double minZoom = 10.0;
  static const double maxZoom = 20.0;

  // ==================== UI Dimensions ====================

  /// Mobile breakpoint width in pixels
  /// Screens narrower than this are considered mobile
  static const double mobileBreakpoint = 768.0;

  /// Mobile dialog size as percentage of screen
  static const double mobileDialogWidthPercent = 0.8;
  static const double mobileDialogHeightPercent = 0.8;
  static const double mobileDialogTopPercent = 0.1;

  /// Desktop dialog size as percentage of screen
  static const double desktopDialogWidthPercent = 0.5;
  static const double desktopDialogHeightPercent = 0.5;
  static const double desktopDialogTopPercent = 0.25;

  /// Debug panel height as percentage of screen
  static const double debugPanelHeightPercent = 0.5;

  /// Map height with debug panel as percentage of screen
  static const double mapWithDebugHeightPercent = 0.7;

  // ==================== Marker Dimensions ====================

  /// Standard marker width in pixels
  static const double markerWidth = 30.0;

  /// Standard marker height in pixels (teardrop shape)
  static const double markerHeight = 40.0;

  /// Icon offset from top of marker in pixels
  static const double markerIconTopOffset = 1.0;

  /// Marker icon size
  static const double markerIconSize = 16.0;

  /// Emoji icon font size in markers
  static const double markerEmojiFontSize = 12.0;

  // ==================== Animation Durations ====================

  /// Debug panel animation duration
  static const int debugPanelAnimationMs = 300;

  /// Mobile hint display duration in seconds
  static const int mobileHintDurationSec = 4;

  /// Fade animation duration
  static const int fadeAnimationMs = 300;

  /// Success message duration
  static const int successMessageDurationSec = 2;

  // ==================== Search & API ====================

  /// Maximum number of search results to display
  static const int maxSearchResults = 10;

  /// LocationIQ search API limit
  static const int locationIQSearchLimit = 10;

  // ==================== Spacing & Padding ====================

  /// Standard padding for containers
  static const double standardPadding = 16.0;

  /// Mini button spacing
  static const double miniButtonSpacing = 8.0;

  /// Button group spacing
  static const double buttonGroupSpacing = 50.0;

  /// Status indicator spacing
  static const double statusIndicatorSpacing = 44.0;

  // ==================== UI Positioning ====================

  /// Top padding offset for positioned widgets (after safe area)
  static const double topWidgetOffset = 16.0;

  /// Bottom widget offset
  static const double bottomWidgetOffset = 16.0;

  /// Side widget offset
  static const double sideWidgetOffset = 16.0;

  // ==================== Shadow & Elevation ====================

  /// Shadow blur radius for containers
  static const double shadowBlurRadius = 4.0;

  /// Shadow offset Y
  static const double shadowOffsetY = 2.0;

  /// Shadow opacity for light shadows
  static const double shadowOpacityLight = 0.1;

  /// Shadow opacity for medium shadows
  static const double shadowOpacityMedium = 0.2;

  /// Shadow opacity for heavy shadows
  static const double shadowOpacityHeavy = 0.3;

  // ==================== Opacity Values ====================

  /// Background overlay opacity
  static const double overlayOpacity = 0.9;

  /// Disabled element opacity
  static const double disabledOpacity = 0.5;

  /// Hover opacity
  static const double hoverOpacity = 0.1;

  // ==================== Border Radius ====================

  /// Standard border radius for cards and containers
  static const double standardBorderRadius = 12.0;

  /// Small border radius for badges
  static const double smallBorderRadius = 8.0;

  /// Large border radius for modals
  static const double largeBorderRadius = 20.0;

  /// Pill border radius for status indicators
  static const double pillBorderRadius = 20.0;

  // ==================== Debug Configuration ====================

  /// Enable debug features in production
  /// Set to false for release builds
  static const bool enableDebugFeatures = true;

  /// Enable debug logging
  static const bool enableDebugLogging = true;

  // ==================== Feature Flags ====================

  /// Enable OSM POI integration
  static const bool enableOSMPOIs = true;

  /// Enable community features
  static const bool enableCommunityFeatures = true;

  /// Enable search functionality
  static const bool enableSearch = true;
}