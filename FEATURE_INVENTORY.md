# Popi Biking Zen Mode - Complete Feature Inventory

**Last Updated:** 2025-11-20
**App Version:** v4.1.0 - Enhanced Hazard System & Multi-Profile Routing

---

## Overview
This is a comprehensive Flutter-based cycling navigation app with both 2D and 3D map capabilities, turn-by-turn navigation, Points of Interest (POIs), community hazard reporting, real-time location tracking, and user profile management with Firebase authentication.

---

## 1. MAP VISUALIZATION & DISPLAY

### 1.1 2D Map System (MapScreen)
**Availability:** Both platforms (Web & Native)
**Key Files:**
- `lib/screens/map_screen.dart`
- `lib/providers/map_provider.dart`
- `lib/services/map_service.dart`

**Features:**
- **Multiple Map Layers** (7 options):
  - OpenStreetMap Standard (Free baseline)
  - OpenCycleMap (Thunderforest - cycling-specific with bike routes)
  - Thunderforest Cycle (Premium cycling map with elevation)
  - Thunderforest Outdoors (Off-road cycling)
  - CyclOSM (Community cycling map focused on bike infrastructure)
  - Satellite (MapTiler aerial imagery)
  - Terrain (MapTiler topographic with elevation)
- **Layer Picker Dialog** - Bottom sheet to switch between map styles
- **Real-time GPS Location** - Blue puck showing user position
- **User Location Marker** - Changes between dot (exploration) and arrow (navigation)
- **Route Rendering** - Polylines with color-coded segments
- **Smart Map Bounds** - 3x3 extended bounds loading for smooth panning
- **Auto-reload Logic** - 10% buffer zone triggers before reloading POIs
- **Map Rotation** - Supports rotation in navigation mode
- **Zoom Controls** - Manual zoom in/out with current zoom level display
- **Auto-center on GPS** - Configurable threshold (3m navigation, 25m exploration)

### 1.2 3D Map System (MapboxMapScreenSimple)
**Availability:** Native only (iOS/Android)
**Key Files:**
- `lib/screens/mapbox_map_screen_simple.dart`
- `lib/screens/mapbox_map_screen_simple_stub.dart` (Web stub)

**Features:**
- **3D Mapbox Styles** (3 options):
  - Mapbox Streets 3D
  - Mapbox Outdoors 3D (terrain optimized for cycling)
  - Wike 3D (Custom cycling style)
- **3D Buildings & Terrain**
- **Seamless 2D/3D Switching** - Preserves map bounds between views
- **Dual-Marker Navigation System** (v4.0.0):
  - Mapbox location puck (blue) shows real GPS position with bearing arrow
  - Purple dot marker shows snapped position on route
  - Both markers visible simultaneously during navigation
  - Simplified configuration with standard puck bearing display
- **Same Navigation Features** as 2D map
- **Platform Detection** - Automatically disabled on Web

### 1.3 Map Interaction
**Availability:** Both 2D and 3D maps
**Key Files:**
- `lib/screens/map_screen.dart`

**Features:**
- **Long Press Context Menu**:
  - "Add Community POI here"
  - "Report Hazard here"
  - "Calculate a route to"
- **Tap on Markers** - Opens detail dialogs
- **Search Result Marker** - Grey circle with red + symbol
- **Center on Location Button** - Snap back to GPS position
- **Manual POI Reload Button** - Orange refresh button
- **Compass Rotation Toggle** (Native only) - Purple button

---

## 2. NAVIGATION SYSTEM

### 2.1 Route Planning & Calculation
**Availability:** Both maps
**Key Files:**
- `lib/services/routing_service.dart`
- `lib/utils/route_calculation_helper.dart`
- `lib/widgets/dialogs/route_selection_dialog.dart`

**Features:**
- **Multi-Profile Routing** (v4.1.0) - Calculates routes for all 3 transport profiles simultaneously:
  - **Car Route** (GraphHopper 'car' profile - red card with 🚗 icon)
  - **Bike Route** (GraphHopper 'bike' profile - green card with 🚴 icon)
  - **Foot Route** (GraphHopper 'foot' profile - blue card with 🚶 icon)
  - Parallel API calls for faster results
  - Hazard detection for each route
- **Route Selection Carousel** (v4.1.0):
  - Horizontal swipeable PageView with route cards
  - Each card shows: profile icon, distance, duration, hazard count
  - Page indicators (dots) at bottom
  - Auto-select last used profile on load
  - "START NAVIGATION" button starts selected route
- **Route Metadata**:
  - Distance (km)
  - Duration (minutes)
  - Turn-by-turn instructions (GraphHopper)
  - Path details (street names, lanes, road class, max speed, surface)
  - Community hazards on route
- **Route Polylines** - Rendered below markers with white borders
- **GraphHopper API Integration** - Powered by GraphHopper Routing API

### 2.2 Turn-by-Turn Navigation
**Availability:** Both maps
**Key Files:**
- `lib/providers/navigation_provider.dart`
- `lib/services/navigation_engine.dart`
- `lib/widgets/navigation_card.dart`
- `lib/models/maneuver_instruction.dart`

**Features:**
- **Navigation Card Overlay** - Persistent top card with:
  - Next maneuver icon and instruction
  - Distance to next maneuver
  - Remaining distance and time
  - Progress bar
  - Current speed
  - ETA range (with +/- 15 min buffer)
  - Off-route distance indicator with timestamp
- **Maneuver Detection**:
  - Turn left/right
  - Slight left/right
  - Sharp left/right
  - Continue straight
  - U-turn
  - Roundabout entry/exit
- **Navigation Modes**:
  - Exploration Mode (North-up, manual zoom)
  - Navigation Mode (Direction-up, auto-zoom)
- **Auto-Zoom** - Speed-based zoom adjustment:
  - Stopped: Zoom 18
  - Slow (< 5 km/h): Zoom 17.5
  - Medium (5-15 km/h): Zoom 17
  - Fast (15-25 km/h): Zoom 16.5
  - Very fast (> 25 km/h): Zoom 16
- **Map Rotation** - Rotates map to face direction of travel
- **GPS Breadcrumb Tracking** - 5 breadcrumbs over 20s for smooth rotation
- **Bearing Smoothing** - 90% new bearing, 10% old bearing for stable rotation
- **Wakelock** - Keeps screen on during navigation (Native only)
- **Landscape Mode Support** - Navigation card on left, map on right

### 2.3 Off-Route & Rerouting
**Availability:** Both maps
**Key Files:**
- `lib/providers/navigation_provider.dart`
- `lib/services/navigation_engine.dart`

**Features:**
- **Speed-Based Off-Route Detection**:
  - **< 15 km/h**: 20m threshold (base)
  - **15-30 km/h**: 30m threshold
  - **30-50 km/h**: 40m threshold
  - **> 50 km/h**: 50m threshold
- **Automatic Rerouting**:
  - 10-second cooldown between reroutes
  - 10-meter position threshold to prevent duplicate reroutes
  - Maintains original route type (fastest/safest/shortest)
  - Toast notifications for reroute status
- **Off-Route Toast Notifications** - Distance from route displayed
- **Manual Recalculation** - User can trigger reroute from dialog

### 2.4 Arrival Detection & Parking Finder
**Availability:** Both maps
**Key Files:**
- `lib/providers/navigation_provider.dart`
- `lib/widgets/arrival_dialog.dart`
- `lib/screens/mapbox_map_screen_simple.dart`
- `lib/screens/map_screen.dart`

**Features:**
- **Arrival Threshold**: 20 meters to destination
- **GPS Accuracy Check**: < 10m accuracy required
- **Arrival Dialog** - Shows when user reaches destination with:
  - Congratulations message
  - Final distance traveled
  - "End Navigation" button (red, ends navigation and closes dialog)
  - "Find a parking" button (blue, searches for nearby bicycle parking)
- **Find a Parking Feature**:
  - Automatically ends navigation
  - Zooms to 500m radius around destination
  - Enables OSM POIs and filters to bike_parking type only
  - Loads and displays all bicycle parking spots within 500m
  - Shows toast notification
- **Navigation State Persistence** - Keeps navigation active until user action

### 2.5 Navigation Controls
**Availability:** Both maps
**Key Files:**
- `lib/widgets/navigation_controls.dart`

**Features:**
- **End Navigation Button** - Red stop button
- **Mute Voice Button** (UI only, voice not implemented)
- **Auto-Zoom Toggle** (2D & 3D) - Enable/disable speed-based zoom

### 2.6 Traveled Route Visualization
**Availability:** Both maps (during navigation)
**Key Files:**
- `lib/screens/mapbox_map_screen_simple.dart`
- `lib/screens/map_screen.dart`

**Features:**
- **Breadcrumb Trail Effect** - Route behind you shown in lighter color
- **Efficient Delta Updates** - Only updates segments that changed state (remaining → traveled)
- **Visual Styling**:
  - **Traveled segments**: Lighter color (70% original + 30% white, 60% opacity)
  - **Traveled line width**: 4.0px (thinner)
  - **Remaining segments**: Original surface color, 6.0px width
- **Smart Updates** - Uses `setStyleLayerProperty()` to update only changed segments
- **Performance Optimized** - Caches segment metadata to avoid full route redraws

---

## 3. POINTS OF INTEREST (POIs)

### 3.1 OSM POIs (OpenStreetMap)
**Availability:** Both maps
**Key Files:**
- `lib/services/osm_service.dart`
- `lib/providers/osm_poi_provider.dart`
- `lib/models/cycling_poi.dart`
- `lib/widgets/osm_poi_selector_button.dart`
- `lib/utils/poi_utils.dart`

**Features:**
- **POI Types** (8 categories):
  - Bicycle Parking 🅿️
  - Repair Station 🔧
  - Charging Station ⚡ (bicycle)
  - Bike Shop 🛒
  - Drinking Water 💧
  - Water Tap 🚰
  - Toilets 🚻
  - Shelter 🏠
- **Multi-Choice POI Selector** - Dropdown menu with:
  - "None of these" (grey button, hides all POIs)
  - Individual POI type checkboxes with emojis
  - "All of these" (blue button, shows all 8 types)
  - Auto-closes on selection
  - Counter badge shows filtered POI count
- **Client-Side Filtering** - Fetch all POIs once, filter instantly on selection change
- **Overpass API Integration** - Queries OSM data in real-time
- **Smart Bounding Box** - Extended 3x3 bounds for smooth panning
- **Timeout Handling** - Fallback to 50% smaller bounds on 504 errors
- **Background Loading** - Non-blocking POI refresh
- **POI Markers** - Blue circular markers with emoji icons
- **POI Detail Dialog** - Shows name, type, address, phone, website
- **Route to POI** - Calculate route from context menu
- **Zoom-Based Visibility** - Auto-disable at zoom ≤ 12
- **Shared Filtering Logic** - POIUtils.filterPOIsByType() used by both 2D and 3D maps

### 3.2 Community POIs (User-Contributed)
**Availability:** Both maps
**Key Files:**
- `lib/providers/community_provider.dart`
- `lib/services/firebase_service.dart`
- `lib/screens/community/poi_management_screen.dart`
- `lib/widgets/dialogs/community_poi_detail_dialog.dart`

**Features:**
- **Firebase Firestore Backend** - Cloud storage for community data
- **POI Types** - Same as OSM categories
- **Add POI Screen**:
  - Name, type, description
  - Address, phone, website
  - GPS coordinates (auto-filled from long-press)
  - Metadata support
- **Edit POI** - Update existing community POIs
- **Delete POI** - Remove community POIs
- **POI Markers** - Green circular markers with emoji icons
- **POI Detail Dialog** - Shows full POI information with edit/delete options
- **Route to POI** - Calculate route from detail dialog
- **Toggle Visibility** - Green button on right side
- **Bounds-Based Loading** - Only loads POIs in visible area
- **Background Refresh** - Auto-reloads after CRUD operations

---

## 4. HAZARD & WARNING SYSTEM

### 4.1 Community Hazards (Enhanced v4.1.0)
**Availability:** Both maps
**Key Files:**
- `lib/providers/community_provider.dart`
- `lib/services/firebase_service.dart`
- `lib/screens/community/hazard_report_screen.dart`
- `lib/widgets/dialogs/warning_detail_dialog.dart`
- `lib/models/community_warning.dart`
- `lib/services/audio_announcement_service.dart` (v4.1.0)
- `lib/config/poi_type_config.dart` (v4.1.0)

**Features:**
- **Enhanced Hazard Types** (v4.1.0 - 9 total):
  - 🕳️ Pothole (30 day expiration)
  - 🚧 Construction (60 day expiration)
  - ⚠️ Dangerous Intersection (90 day expiration)
  - 🛤️ Poor Surface (30 day expiration)
  - 🪨 Debris (7 day expiration)
  - 🚗 Traffic Hazard (14 day expiration)
  - ⛰️ Steep Section (90 day expiration)
  - 💧 Flooding (7 day expiration)
  - ❓ Other (30 day expiration)
- **Severity Levels** (v4.1.0): Low, Medium, High (Critical removed)
- **Community Voting System** (v4.1.0):
  - Upvote/downvote hazards (one vote per user)
  - Vote score calculation (upvotes - downvotes)
  - Color-coded score display (green for positive, red for negative)
  - Transaction-safe voting to prevent duplicates
- **Verification System** (v4.1.0):
  - Users can verify hazards
  - 3-verification threshold for "verified" badge
  - Green checkmark badge on verified hazards
  - Verification counter (X/3) display
- **Status Management** (v4.1.0):
  - Active, Resolved, Disputed, Expired
  - Reporter-only "Mark as Resolved" button
  - Status badge with color coding
  - Confirmation dialog for status changes
- **Type-Based Auto-Expiration** (v4.1.0):
  - Automatic expiration based on hazard type (7-90 days)
  - Expiration date auto-calculated on creation
  - Migration utility for existing hazards
- **Report Hazard Screen**:
  - Title and description
  - Type selection with emojis (from POITypeConfig)
  - Severity selection
  - GPS coordinates (auto-filled from long-press)
  - Auto-calculated expiration date
  - Reported by (user ID)
- **Enhanced Warning Detail Dialog** (v4.1.0):
  - Voting buttons (upvote/downvote) with counts
  - Vote score display with color
  - Verification button and counter
  - Verified badge (green checkmark)
  - Status badge display
  - "Mark as Resolved" button (reporter only)
  - Time since report display
  - Optimistic UI updates
- **Edit Hazard** - Update existing warnings
- **Delete Hazard** - Reporter-only deletion
- **Warning Markers** - Orange circular markers with emoji icons
- **Toggle Visibility** - Orange button on right side
- **Bounds-Based Loading** - Only loads warnings in visible area
- **Audio Announcements** (v4.1.0):
  - TTS hazard warnings at 100m threshold
  - Severity-based messaging
  - Verified status in announcement
  - Hazard title inclusion
  - Enable/disable toggle in profile settings
  - Test audio button
  - Prevents duplicate announcements

### 4.2 Route Hazard Detection
**Availability:** Both maps (during navigation)
**Key Files:**
- `lib/services/route_hazard_detector.dart`
- `lib/models/route_warning.dart`

**Features:**
- **On-Route Detection** - Detects community hazards within 20m of route
- **Distance Calculation** - Calculates distance along route to each hazard
- **Hazard Markers on Map** - Shows warning icons on route
- **Warning List in Navigation Card** - Expandable section with all warnings
- **Distance to Warning** - Real-time distance updates
- **Warning Icon in Maneuver Area** - Shows next warning < 100m away

### 4.3 Road Surface Warnings
**Availability:** Both maps (during navigation)
**Key Files:**
- `lib/services/road_surface_analyzer.dart`
- `lib/services/route_surface_helper.dart`

**Features:**
- **Surface Detection** - Analyzes GraphHopper path details
- **Surface Types**:
  - Gravel/Unpaved
  - Dirt/Sand/Grass/Mud
  - Cobblestone
- **Surface Warning Markers** - Orange circular markers with surface-specific icons
- **Color-Coded Route Segments**:
  - Green: Paved surface
  - Orange: Gravel/Unpaved
  - Red: Dirt/Poor surface
- **Warning Distance** - Shows distance to surface changes
- **Merged Warning System** - Combines community and surface warnings

---

## 5. SEARCH & GEOCODING

### 5.1 Address Search
**Availability:** Both maps
**Key Files:**
- `lib/providers/search_provider.dart`
- `lib/services/geocoding_service.dart`
- `lib/widgets/search_bar_widget.dart`
- `lib/models/search_result.dart`

**Features:**
- **Search Bar** - Slides down from top when yellow button pressed
- **3-Second Debounce** - Auto-search after 3s of typing
- **Manual Search** - Press search button or ENTER key
- **Coordinate Parsing** - Supports lat,lon or lat lon formats
- **Geocoding APIs**:
  - Nominatim (primary, free)
  - Photon (fallback)
- **Bounded Search** - Searches within map viewport first
- **Expand Search** - "Extend the search" button for unbounded results
- **Search Results List** - Shows up to 20 results with icons
- **Result Tap** - Centers map and shows marker
- **Routing Dialog** - Tap result to calculate route
- **Clear Search** - X button to clear query
- **Close Search** - Dismisses search bar

### 5.2 Search Result Interaction
**Availability:** Both maps
**Key Files:**
- `lib/widgets/search_result_tile.dart`

**Features:**
- **Result Marker** - Grey circle with red + on map
- **Route Calculation** - Single-option dialog for routing
- **Result Icons** - Type-specific icons (address, city, POI, etc.)
- **Distance from Center** - Shows distance in result list

---

## 6. LOCATION & GPS

### 6.1 Location Tracking
**Availability:** Both maps
**Key Files:**
- `lib/services/location_service.dart`
- `lib/providers/location_provider.dart`
- `lib/models/location_data.dart`

**Features:**
- **Geolocator Package** - Native GPS access
- **Real-time Location Stream** - Continuous GPS updates (every 3 seconds)
- **Location Permissions** - Request & handle permissions
- **Location Accuracy** - Displays GPS accuracy in meters
- **Speed Tracking** - Current speed in m/s and km/h
- **Heading** - Compass direction (0-360°)
- **Altitude** - Elevation data
- **iOS & Android Support** - Platform-specific implementations
- **Web Support** - Browser geolocation API

### 6.2 Compass (Native Only)
**Availability:** Native only (iOS/Android)
**Key Files:**
- `lib/providers/compass_provider.dart`

**Features:**
- **Compass Heading** - Magnetic north direction
- **Compass Rotation Toggle** - Purple button (2D map only)
- **Threshold-Based Rotation** - Only rotates on 5° change
- **Automatic in Navigation** - Uses travel direction instead of compass

---

## 7. DEBUG & LOGGING

### 7.1 Debug Overlay
**Availability:** Both maps
**Key Files:**
- `lib/widgets/debug_overlay.dart`
- `lib/providers/debug_provider.dart`

**Features:**
- **Debug Toggle** - Red bug button on map
- **Floating Debug Panel** - Top-right overlay
- **Message Log** - Last 10 debug messages
- **Color Coding**:
  - Red: Errors
  - Orange: Warnings
  - Blue: Info
  - Green: Success
- **Auto-Fade** - Messages fade after 10s
- **No Duplicates** - Prevents duplicate consecutive messages
- **Release Mode Support** - Works in both debug and release builds

### 7.2 Logging Services
**Availability:** Both platforms
**Key Files:**
- `lib/utils/app_logger.dart`
- `lib/utils/api_logger.dart`
- `lib/services/debug_service.dart`

**Features:**
- **AppLogger** - Console logging with tags and colors
- **ApiLogger** - Logs all API calls to Firestore
- **DebugService** - Tracks user actions
- **Log Categories**:
  - API calls
  - Firebase operations
  - Location updates
  - Map events
  - Navigation events
  - Routing
  - POI loading
  - Errors & warnings
- **Circular Buffer** - Keeps last 100 log entries in memory
- **Broadcast Stream** - Real-time log updates to debug overlay

---

## 8. UI/UX FEATURES

### 8.1 Responsive Design
**Availability:** Both maps
**Key Files:**
- `lib/utils/responsive_helper.dart`

**Features:**
- **Orientation Support** - Portrait & landscape layouts
- **Landscape Navigation** - Card on left (50%), map on right (50%)
- **Portrait Navigation** - Card on top, map below
- **Platform Detection** - Web vs Native optimizations
- **Safe Area Padding** - Respects notches and status bars

### 8.2 Toast Notifications
**Availability:** Both maps
**Key Files:**
- `lib/services/toast_service.dart`

**Features:**
- **Toast Types**:
  - Success (green)
  - Error (red)
  - Warning (orange)
  - Info (blue)
- **Navigation-Aware Positioning** - Adjusts position when nav card is visible
- **Duration Control** - Short/long display times
- **Dismissible** - Swipe to dismiss

### 8.3 Dialogs & Bottom Sheets
**Availability:** Both maps
**Key Files:**
- `lib/widgets/dialogs/`

**Features:**
- **POI Detail Dialog** - Shows OSM POI details
- **Community POI Detail Dialog** - Shows community POI with edit/delete
- **Warning Detail Dialog** - Shows hazard details with edit/delete
- **Route Selection Dialog** - Choose between 3 route types
- **Arrival Dialog** - Congratulates on arrival
- **Off-Route Dialog** - Offers reroute or dismiss
- **Layer Picker** - Bottom sheet for map style selection
- **Transparent Barriers** - See-through dialog backgrounds

### 8.4 Map Toggle Buttons
**Availability:** Both maps
**Key Files:**
- `lib/widgets/map_toggle_button.dart`

**Features:**
- **OSM POI Toggle** - Blue button with count badge
- **Community POI Toggle** - Green button with count badge
- **Warning Toggle** - Orange button with count badge
- **Favorites & Destinations Toggle** - Yellow button with star icon and count badge
- **Disabled State** - Grey when zoom ≤ 12
- **Count Display** - Shows number of visible items
- **99+ Limit** - OSM POIs show full count, others cap at 99+
- **Navigation Mode Visibility** - Community POIs and Favorites toggles hidden during navigation
- **Auth-Based Visibility** - Favorites toggle hidden when user not logged in

---

## 9. USER AUTHENTICATION & PROFILES

### 9.1 Authentication System
**Availability:** Both maps
**Key Files:**
- `lib/providers/auth_provider.dart`
- `lib/screens/auth/login_screen.dart`
- `lib/screens/auth/register_screen.dart`
- `lib/screens/auth/profile_screen.dart`

**Features:**
- **Email/Password Authentication**:
  - User registration with email validation
  - Secure login with Firebase Auth
  - Password requirements enforced
  - Duplicate email detection
- **Google Sign-In**:
  - iOS: Native Google Sign-In with iOS OAuth client
  - Web/PWA: Web OAuth client for browser authentication
  - Automatic account creation on first sign-in
  - Photo URL and display name sync
- **User Profile Management**:
  - Display name, email, phone number
  - Profile photo from Google account
  - Firebase user UID tracking
  - Real-time profile updates
- **Authentication Flow**:
  - Persistent login state across app restarts
  - Automatic logout functionality
  - Profile button in top-right corner (both maps)
  - Login/Register/Profile screen navigation
  - GlobalKey management to prevent duplicate dialogs

### 9.2 User Preferences & History
**Availability:** Both maps (authenticated users only)
**Key Files:**
- `lib/providers/auth_provider.dart`
- `lib/models/user_profile.dart`
- `lib/widgets/search_history_tabs.dart`

**Features:**
- **Recent Search History** (Last 20):
  - Auto-saves searches when user performs search
  - Stored in Firestore user profile
  - Displayed in search history tab with search icon
  - Tap to re-run search query
  - Chronological ordering (newest first)

- **Recent Destinations** (Last 20):
  - Auto-saves when user selects a route
  - Names auto-populated from search results or POI names
  - Coordinate fallback for unnamed locations (lat, lon format)
  - Displayed in search tab with orange teardrop icon (📍)
  - Tap to navigate to location
  - Edit and delete functionality in profile screen

- **Favorite Locations** (Max 20):
  - Add/remove from any location on map
  - Available in: POI dialogs, Community POI dialogs, Search results, Long-press menus, Favorites markers
  - Displayed in search tab with yellow star icon (⭐)
  - Tap to navigate to location
  - Edit and delete functionality in profile screen
  - Limit enforcement with user-facing warning toast
  - Success/info toasts for add/remove actions

- **User Preferences** (v4.1.0):
  - **Default Route Profile** - Preferred transport mode (car/bike/foot)
    - Dropdown selector in profile settings
    - Visual indicator in route carousel (star icon)
  - **Last Used Route Profile** - Auto-saved when starting navigation
    - Determines initial carousel page
    - Read-only display in profile settings
  - **Appearance Mode** - Theme preference (system/light/dark)
    - Dropdown selector in profile settings
    - Auto-applies system theme by default
  - **Audio Alerts Toggle** - Enable/disable hazard announcements
    - Switch in profile settings
    - Test audio button when enabled
    - Syncs with AudioAnnouncementService

### 9.3 Profile Screen
**Availability:** Both maps (authenticated users only)
**Key Files:**
- `lib/screens/auth/profile_screen.dart`

**Features:**
- **User Information Display**:
  - Profile photo (from Google or default avatar)
  - Display name
  - Email address
  - Registration date
  - Logout button

- **Expandable History Sections**:
  - Recent Searches (count badge, scrollable list)
  - Recent Destinations (count badge, scrollable list with edit/delete)
  - Favorites (count badge, scrollable list with edit/delete)

- **CRUD Operations**:
  - Edit destination/favorite names via dialog
  - Delete destinations/favorites via trash icon
  - Real-time Firestore updates
  - Immediate UI refresh after changes
  - Confirmation dialogs for destructive actions

### 9.4 Favorites & Destinations Map Display
**Availability:** Both maps (authenticated users only)
**Key Files:**
- `lib/providers/favorites_visibility_provider.dart`
- `lib/screens/map_screen.dart`
- `lib/screens/mapbox_map_screen_simple.dart`

**Features:**
- **Map Markers**:
  - Destination markers: Orange circle with teardrop icon (📍)
  - Favorite markers: Yellow circle with star icon (⭐)
  - Same size as community POI markers
  - Tap to open detail dialog
  - Displayed on both 2D and 3D maps

- **Visibility Toggle**:
  - Yellow button with star icon
  - Positioned between warnings and zoom controls
  - Shows count of destinations + favorites
  - Enabled by default on app start
  - Auto-disabled during navigation mode
  - Hidden when user not logged in
  - Real-time updates when favorites/destinations change

- **Detail Dialogs**:
  - Location name with icon (📍 or ⭐)
  - Coordinates display
  - "Route To" button (calculates route)
  - "Remove from Destinations/Favorites" button (red, left-aligned)
  - "Close" button
  - Same design pattern as POI dialogs

### 9.5 Search History Integration
**Availability:** Both maps (authenticated users only)
**Key Files:**
- `lib/widgets/search_bar_widget.dart`
- `lib/widgets/search_history_tabs.dart`

**Features:**
- **3-Tab Search Interface**:
  - Tab 1: Recent Searches (🔍 icon)
  - Tab 2: Recent Destinations (📍 icon, orange)
  - Tab 3: Favorites (⭐ icon, yellow)
  - Shows when search bar open with empty query
  - Matching search result tile styling (16px font, grey dividers)
  - Empty states for each tab

- **Interaction**:
  - Tap search to re-run query
  - Tap destination/favorite to navigate
  - Auto-closes search bar on selection
  - Seamless integration with search flow

---

## 10. NAVIGATION CARD FEATURES (Detailed)

### 10.1 Main Display
**Availability:** Both maps (during navigation)
**Key Files:**
- `lib/widgets/navigation_card.dart`

**Features:**
- **Next Maneuver Section**:
  - Maneuver icon (48x48)
  - Instruction text
  - Distance to maneuver
  - GraphHopper comparison (amber box)
  - Warning triangle (if warning < 100m)
  - Speed limit sign (European circular style)
- **Route Summary**:
  - Remaining distance (km)
  - Remaining time (min)
  - Off-route indicator with timestamp
  - ETA range badge (optimistic-pessimistic)
- **Progress Bar** - Visual route completion
- **Current Speed** - Real-time km/h display
- **Speed Averages**:
  - Average with stops (slower → faster)
  - Average without stops

### 10.2 Warnings Section
**Availability:** Both maps (during navigation)
**Features:**
- **Expandable/Collapsible** - Tap header to toggle
- **Auto-Collapse** - Collapses after 3s (v4.0.0 optimization)
- **Merged Warnings** - Community + surface warnings
- **Color-Coded Cards**:
  - Red: Community hazards
  - Orange: Surface warnings
- **Distance Display** - Real-time distance to each warning
- **Warning Icons** - Type-specific emojis
- **Clear Road Message** - Shows when no warnings

### 10.3 GraphHopper Data Section (Collapsible)
**Availability:** Both maps (during navigation)
**Features:**
- **Live Path Details**:
  - Street name
  - Street reference (e.g., "A1")
  - Street destination
  - Lanes
  - Road class
  - Max speed
  - Surface type
- **Data Chips** - Color-coded badges for each detail
- **GraphHopper Instruction** - Full text instruction from API

### 10.4 Maneuvers Section (Debug, Collapsible)
**Availability:** Both maps (during navigation)
**Features:**
- **All Maneuvers List** - Shows every turn on route
- **Distance Indicators** - Positive (ahead) or negative (passed)
- **Current Maneuver Highlight** - Green border
- **Maneuver Icons** - Type-specific emojis
- **Relative Distances** - Distance from current position

---

## 11. ANALYTICS & STATISTICS

### 11.1 Speed Tracking
**Availability:** Both maps (during navigation)
**Key Files:**
- `lib/providers/navigation_provider.dart`
- `lib/models/navigation_state.dart`

**Features:**
- **Current Speed** - Instant speed in km/h
- **Average Speed (with stops)** - Total distance / total time
- **Average Speed (without stops)** - Total distance / moving time
- **Moving Time Tracking** - Only counts when speed ≥ 0.5 m/s
- **Distance Traveled** - Cumulative distance since navigation start
- **Time Elapsed** - Total time since navigation start
- **Time Moving** - Time spent moving (not stopped)

### 11.2 ETA Calculation
**Availability:** Both maps (during navigation)
**Features:**
- **Base ETA** - Calculated from remaining distance and current speed
- **ETA Range** - Shows ± 15 minutes buffer
- **Dynamic Updates** - Recalculates every 3 seconds
- **Display Format** - Optimistic time - Pessimistic time (e.g., "10:30-10:45")

---

## 12. PLATFORM-SPECIFIC FEATURES

### 12.1 Native-Only Features
**Availability:** iOS & Android only

**Features:**
- **3D Mapbox Maps** - Full 3D terrain and buildings
- **Compass Rotation** - Magnetic heading support
- **Better GPS Accuracy** - Native location services
- **Wakelock** - Screen stays on during navigation
- **Haptic Feedback** - Vibration on long-press
- **Background Location** - Continues tracking in background
- **Google Sign-In** - Native Google authentication with iOS OAuth

### 12.2 Web-Specific Features
**Availability:** Web/PWA only

**Features:**
- **Browser Geolocation** - HTML5 Geolocation API
- **2D Maps Only** - 3D button hidden
- **No Compass** - Compass features disabled
- **Responsive Layout** - Adapts to browser window
- **Progressive Web App** - Can be installed on home screen
- **Google Sign-In** - Web OAuth client for browser authentication

---

## 13. BACKEND & DATA SOURCES

### 13.1 External APIs
**Key Files:**
- `lib/config/api_keys.dart`

**Services:**
- **GraphHopper** - Routing & turn-by-turn navigation (API key required)
- **Nominatim** - Geocoding (free)
- **LocationIQ** - Geocoding and reverse geocoding (API key required)
- **Photon** - Geocoding fallback (free)
- **Overpass API** - OSM POI queries (free)
- **Thunderforest** - Cycling map tiles (API key required)
- **MapTiler** - Satellite & terrain tiles (API key required)
- **Mapbox** - 3D maps and location services (API key required)

### 13.2 Firebase Integration
**Key Files:**
- `lib/services/firebase_service.dart`
- `lib/providers/auth_provider.dart`

**Features:**
- **Firebase Authentication**:
  - Email/Password authentication
  - Google Sign-In (iOS & Web)
  - User session management
  - Profile photo sync

- **Firestore Database**:
  - `cyclingPOIs` collection - Community POIs
  - `communityWarnings` collection - Hazard reports
  - `apiLogs` collection - API call logs
  - `debugActions` collection - User action logs
  - `users` collection - User profiles with:
    - `recentSearches` (array, max 20)
    - `recentDestinations` (array, max 20, SavedLocation objects)
    - `favoriteLocations` (array, max 20, SavedLocation objects)
    - `defaultRouteProfile` (string: 'car', 'bike', or 'foot')
    - User metadata (displayName, email, photoURL, createdAt, updatedAt)

- **Geohashing** - Efficient spatial queries
- **Bounds Queries** - Latitude/longitude range filtering
- **Real-time Streams** - Live data updates
- **CRUD Operations** - Create, Read, Update, Delete for POIs, warnings, and user data

---

## 14. TECHNICAL STACK & DEPENDENCIES

### 14.1 Core Framework
**Flutter SDK:** >=3.0.0 <4.0.0
**Dart:** Latest stable with Flutter
**App Version:** 1.3.10+3 (App Store version v4.0.0)

### 14.2 State Management
- **flutter_riverpod** ^3.0.1 - State management and dependency injection
- **riverpod** any - Core Riverpod package

### 14.3 Mapping Libraries

**2D Maps:**
- **flutter_map** ^8.2.2 - 2D tile-based maps (OSM, Thunderforest, MapTiler)
- **latlong2** ^0.9.1 - Latitude/longitude coordinates

**3D Maps (Native only):**
- **mapbox_maps_flutter** ^2.6.0 - Mapbox Maps SDK for Flutter
  - 3D terrain and buildings
  - LocationPuck2D for user location display
  - PointAnnotationManager for custom markers
  - Style and camera control APIs

### 14.4 Location Services
- **geolocator** ^14.0.2 - GPS location tracking (iOS CoreLocation, Android FusedLocationProvider)
- **flutter_compass** ^0.8.0 - Compass/heading data
- **wakelock_plus** ^1.3.3 - Keep screen on during navigation

### 14.5 Firebase Services
- **firebase_core** ^4.2.0 - Firebase initialization
- **firebase_auth** ^6.1.1 - User authentication (Email/Password, Google Sign-In)
- **cloud_firestore** ^6.0.3 - NoSQL database for POIs, warnings, user data
- **firebase_crashlytics** ^5.0.3 - Crash reporting
- **google_sign_in** ^6.2.2 - Google OAuth authentication

### 14.6 HTTP & External APIs
- **http** ^1.2.2 - HTTP client for REST API calls
- **flutter_dotenv** ^6.0.0 - Environment variable management for API keys

### 14.7 UI Libraries
- **cupertino_icons** ^1.0.8 - iOS-style icons
- **google_fonts** ^6.2.1 - Custom typography

### 14.8 External API Services (Requires API Keys)
1. **GraphHopper API** - Cycling route calculation and turn-by-turn navigation
2. **Mapbox API** - 3D maps, terrain, location puck services
3. **MapTiler API** - Satellite and terrain tiles for 2D maps
4. **Thunderforest API** - Premium cycling map tiles (OpenCycleMap, Cycle, Outdoors)
5. **LocationIQ API** - Geocoding and reverse geocoding

### 14.9 Free Open Source Services
1. **OpenStreetMap (OSM)** - Base map data and free tile layer
2. **Nominatim** - Free geocoding service (OSM-based)
3. **Photon** - Free geocoding fallback service
4. **Overpass API** - OSM POI data queries
5. **CyclOSM** - Community cycling map tiles

---

## 15. CONFIGURATION & CONSTANTS

### 15.1 Marker Configuration
**Key Files:**
- `lib/config/marker_config.dart`

**Features:**
- **Marker Types**:
  - User Location (12px radius)
  - OSM POI (9px radius)
  - Community POI (9px radius)
  - Warning (10px radius)
  - Search Result (12px radius)
  - Destination (9px radius)
  - Favorite (9px radius)
- **Color Schemes**:
  - User: Blue (#2196F3)
  - OSM POI: Blue (#0000FF)
  - Community POI: Green (#4CAF50)
  - Warning: Orange (#FFE0B2)
  - Search: Grey
  - Destination: Orange (#FFCC80)
  - Favorite: Yellow (#FFD54F)
- **Stroke Width** - 2px for all markers

### 15.2 POI Type Configuration
**Key Files:**
- `lib/config/poi_type_config.dart`

**Features:**
- **POI Emojis** - Type-specific icons (🚲, 🔧, ⚡, 🚰, 🚻, etc.)
- **Warning Emojis** - Hazard-specific icons (⚠️, 🚧, 🚦, ❄️, etc.)
- **Location Emojis** - Destination (📍), Favorite (⭐)
- **POI Names** - Human-readable labels
- **Type Mapping** - OSM tags to internal types

### 15.3 App Theme
**Key Files:**
- `lib/constants/app_theme.dart`
- `lib/constants/app_colors.dart`

**Features:**
- **Color Palette**:
  - Urban Blue (#1976D2)
  - Cycling Green (#4CAF50)
  - Safety Orange (#FF9800)
  - Alert Red (#F44336)
- **Typography** - Consistent font sizes and weights
- **Component Themes** - Buttons, cards, dialogs

---

## FEATURE MATRIX

| Feature Category | 2D Map | 3D Map | Web | Native |
|-----------------|--------|--------|-----|--------|
| **Map Display** | ✅ | ✅ | ✅ | ✅ |
| Multiple Map Layers | ✅ | ✅ | ✅ | ✅ |
| 3D Buildings/Terrain | ❌ | ✅ | ❌ | ✅ |
| **Navigation** | ✅ | ✅ | ✅ | ✅ |
| Turn-by-Turn | ✅ | ✅ | ✅ | ✅ |
| Auto-Zoom | ✅ | ✅ | ✅ | ✅ |
| Map Rotation | ✅ | ✅ | ✅ | ✅ |
| Traveled Route Trail | ✅ | ✅ | ✅ | ✅ |
| Off-Route Detection | ✅ | ✅ | ✅ | ✅ |
| Automatic Rerouting | ✅ | ✅ | ✅ | ✅ |
| **POIs** | ✅ | ✅ | ✅ | ✅ |
| OSM POIs | ✅ | ✅ | ✅ | ✅ |
| Community POIs | ✅ | ✅ | ✅ | ✅ |
| Add/Edit/Delete POIs | ✅ | ✅ | ✅ | ✅ |
| **Hazards** | ✅ | ✅ | ✅ | ✅ |
| Community Warnings | ✅ | ✅ | ✅ | ✅ |
| Route Hazard Detection | ✅ | ✅ | ✅ | ✅ |
| Surface Warnings | ✅ | ✅ | ✅ | ✅ |
| **Search** | ✅ | ✅ | ✅ | ✅ |
| Address Search | ✅ | ✅ | ✅ | ✅ |
| Coordinate Parsing | ✅ | ✅ | ✅ | ✅ |
| **User Features** | ✅ | ✅ | ✅ | ✅ |
| User Authentication | ✅ | ✅ | ✅ | ✅ |
| Search History | ✅ | ✅ | ✅ | ✅ |
| Favorites | ✅ | ✅ | ✅ | ✅ |
| Destination History | ✅ | ✅ | ✅ | ✅ |
| Route Preferences | ✅ | ✅ | ✅ | ✅ |
| **Platform Features** | | | | |
| Compass Rotation | ✅ | ✅ | ❌ | ✅ |
| Haptic Feedback | ✅ | ✅ | ❌ | ✅ |
| Wakelock | ✅ | ✅ | ❌ | ✅ |
| Google Sign-In | ✅ | ✅ | ✅ | ✅ |
| Debug Overlay | ✅ | ✅ | ✅ | ✅ |

---

## SUMMARY STATISTICS

- **Total Screens**: 9 (Splash, 2D Map, 3D Map, POI Management, Hazard Report, Login, Register, Profile, Stubs)
- **Total Providers**: 12 (Navigation, Map, Location, Search, Community, OSM POI, Compass, Debug, Navigation Mode, Auth, User Profile, Favorites Visibility)
- **Total Services**: 17+ (Routing, OSM, Firebase, Location, Geocoding, Navigation Engine, Map, Toast, Debug, Error, Route Hazard Detector, Road Surface Analyzer, Route Surface Helper, API Logger, Conditional POI Loader, iOS Navigation, Auth)
- **Total Models**: 9+ (LocationData, CyclingPOI, CommunityWarning, SearchResult, ManeuverInstruction, RouteWarning, NavigationState, UserProfile, SavedLocation)
- **Map Layers (2D)**: 7
- **Map Styles (3D)**: 3
- **POI Types**: 8
- **Hazard Types**: 5
- **Route Types**: 3 (Fastest, Safest, Shortest)
- **External APIs**: 8
- **Firebase Collections**: 5 (cyclingPOIs, communityWarnings, apiLogs, debugActions, users)
- **Authentication Methods**: 2 (Email/Password, Google Sign-In)
- **User Data Collections**: 3 (Search History, Destinations, Favorites)
- **Max Items per Collection**: 20

---

## RECENT OPTIMIZATIONS & IMPROVEMENTS

### Performance Optimizations
- **Traveled Route Delta Updates** - Only updates segments that change state instead of full redraw
- **Segment Property Updates** - Uses `setStyleLayerProperty()` for efficient color/width changes
- **No More Blinking** - Removed full marker/route redraw on GPS updates:
  - Fixed in turn-by-turn navigation mode
  - Fixed in exploration mode
  - User location shown by Mapbox location puck (auto-updated)
  - POIs/warnings/route update only via listeners when data changes
- **Smart Caching** - Route segment metadata cached for instant updates
- **Client-Side POI Filtering** - Fetch all POIs once, filter instantly without API calls
- **Efficient POI Counter** - Shows accurate filtered count on selector badge

### Navigation Enhancements
- **Breadcrumb Trail** - Visual distinction between traveled and remaining route
- **Bearing Smoothing** - 90/10 ratio for stable map rotation
- **Speed-Based Off-Route** - Dynamic thresholds based on cycling speed
- **ETA Range Display** - Shows realistic time window with buffer
- **Arrival Dialog** - Congratulations message with parking finder option
- **Find a Parking** - Auto-zoom to 500m radius and show bicycle parking at destination
- **Navigation Mode UI Cleanup** - Hide exploration controls during navigation:
  - Reload POIs, map layer/style selectors, 2D/3D switchers hidden
  - Community POIs and Favorites toggles hidden
  - Cleaner interface focused on turn-by-turn guidance
- **v4.0.0 Dual-Marker System (3D Navigation)**:
  - Replaced rotating arrow with simple purple dot marker
  - Show both Mapbox puck (real GPS) and purple dot (snapped position) simultaneously
  - Removed complex bearing/rotation logic that caused issues
  - Simplified LocationComponentSettings to standard puck with bearing
  - Clean, reliable navigation experience with no marker flickering

### User Experience Improvements
- **Multi-Choice POI Selector** - Replace toggle with dropdown menu:
  - Individual type selection with checkboxes
  - "All of these" and "None of these" options
  - Counter shows filtered POI count
  - Instant filtering without API reload
- **Shared Code Architecture** - POIUtils for common filtering logic between 2D and 3D maps
- **Firebase Authentication** - Complete user authentication system:
  - Email/password and Google Sign-In
  - User profiles with favorites and preferences
  - Search history and route preferences
  - Persistent data across devices
- **Favorites System** - Save and manage favorite locations:
  - Up to 20 favorites per user with limit warnings
  - Map markers showing favorites and destinations
  - Detail dialogs with routing and favorite management
  - Proper state display (favorited vs. add to favorites)
- **Search Result Name Persistence** - Actual location names saved instead of generic "Search Result"

### Logging Cleanup
- **Reduced Log Volume** - ~60-70% reduction in high-frequency logs
- **Preserved Critical Logs** - Kept errors, warnings, navigation milestones, user actions
- **Release Mode Support** - Debug overlay now works in production builds

---

## KNOWN LIMITATIONS

1. **Voice Navigation** - No voice turn-by-turn guidance implementation
2. **Route Profiles** - Limited to 3 GraphHopper profiles (car, bike, foot)
3. **Offline Maps** - No offline tile caching
4. **Multi-Language** - Currently English only
5. **Elevation Display** - Not shown in navigation card
6. **Weather Integration** - No real-time weather data
7. **Traffic Data** - No live traffic information
8. **POI Photos** - No image upload for community POIs
9. **Favorites Limit** - Maximum 20 favorites per user
10. **Community POI Editing** - No ability to edit/delete POIs after creation

---

## FUTURE ENHANCEMENT OPPORTUNITIES

### Navigation
- Voice turn-by-turn guidance with audio announcements
- Lane guidance with arrows
- Speed camera alerts
- Live traffic integration
- Alternative route suggestions during navigation
- Route waypoints/via points

### POIs & Community
- Photo upload for POIs/hazards
- Upvote/downvote system for community reports
- User reputation/trust scores
- POI/hazard expiration reminders
- Comments on community reports
- Edit/delete own POIs and hazards
- Increase favorites limit (currently 20)

### Map Features
- Offline map downloads
- Custom route drawing
- Multiple destination routing
- Route sharing (export GPX/KML)
- Heatmap of popular cycling routes
- Import GPX routes

### Analytics
- Ride statistics dashboard
- Calorie tracking
- Elevation profile display
- Speed graphs
- Route comparison
- Monthly/yearly summaries
- Total distance/time tracked

### Social Features
- Friend following
- Group rides
- Route recommendations from friends
- Community leaderboards
- Achievement badges
- Ride sharing
- Social feed of friends' activities

---

## VERSION HISTORY

### v4.1.0 (2025-11-20) - Enhanced Hazard System & Multi-Profile Routing

**Major Features:**
- **Multi-Profile Routing**: Calculate Car/Bike/Foot routes simultaneously with horizontal carousel UI
- **Enhanced Hazard System**: Community voting, verification, status management, and type-based expiration
- **Audio Announcements**: TTS hazard warnings at 100m during navigation
- **User Preferences**: Appearance mode, audio alerts toggle, default profile, and last used profile

**Hazard System Enhancements:**
- Added 4 new hazard types: Dangerous Intersection, Debris, Steep Section, Flooding
- Community voting system (upvote/downvote) with transaction safety
- 3-user verification system with verified badge
- Status management (Active/Resolved/Disputed/Expired)
- Type-based auto-expiration (7-90 days based on hazard type)
- Enhanced warning detail dialog with voting/verification UI
- Reporter-only status updates and deletion
- Removed "Critical" severity level

**Routing Improvements:**
- Parallel route calculation for all 3 transport profiles
- Horizontal swipeable carousel for route selection
- Profile-specific icons and colors (🚗 🚴 🚶)
- Auto-select last used profile
- Hazard count display on each route card
- Page indicators for carousel navigation

**User Profile Enhancements:**
- Appearance mode selector (System/Light/Dark)
- Audio alerts toggle with test button
- Default route profile selector
- Last used route profile tracking
- Preference cards UI with icons

**Technical Improvements:**
- New `MultiProfileRouteResult` model
- `TransportProfile` enum for type safety
- `AudioAnnouncementService` with TTS integration
- Centralized `POITypeConfig` for hazard types
- Migration utility for existing hazard data
- Updated Firestore security rules for voting/verification
- Optimistic UI updates for better UX

**Dependencies Added:**
- flutter_tts ^4.2.0 for audio announcements

**Files Modified:**
- `lib/models/community_warning.dart` - Added voting/verification fields
- `lib/models/user_profile.dart` - Added preference fields
- `lib/services/firebase_service.dart` - Added voting/verification methods
- `lib/services/routing_service.dart` - Added multi-profile routing
- `lib/widgets/dialogs/route_selection_dialog.dart` - Carousel UI
- `lib/widgets/dialogs/warning_detail_dialog.dart` - Enhanced UI
- `lib/screens/community/hazard_report_screen.dart` - New hazard types
- `lib/screens/auth/profile_screen.dart` - Preferences UI
- `lib/config/poi_type_config.dart` - Centralized hazard types

**Files Created:**
- `lib/models/multi_profile_route_result.dart` - Multi-profile data model
- `lib/services/audio_announcement_service.dart` - TTS service
- `lib/utils/firebase_migration.dart` - Migration utility
- `MIGRATION_GUIDE.md` - Database migration instructions
- `UPGRADE_SUMMARY.md` - Implementation progress tracker

### v4.0.0 (2025-11-07) - User Authentication & Profiles
- Firebase Auth integration (Email/Password, Google Sign-In)
- User profiles with preferences
- Recent searches, destinations, and favorites
- Profile screen with edit functionality
- Authentication flow and persistent login

### v3.x (Previous)
- 3D navigation with dual-marker system
- Turn-by-turn navigation
- Community POIs and hazards
- 2D/3D map switching
- OSM POI integration
- Route calculation and preview

---

This comprehensive cycling navigation app provides safe, efficient cycling with community-driven safety features, extensive POI coverage, intelligent turn-by-turn navigation, flexible 2D/3D visualization, and enhanced hazard management with community engagement. 🚴‍♂️
