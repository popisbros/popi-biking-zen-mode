# Wike iOS - Native Swift Cycling Navigation App

## Project Overview

Build a **native iOS Swift cycling navigation app** based on the existing Flutter implementation in `../popi_biking_fresh/`. This is a **3D map only** version (no 2D maps) focused on professional cycling navigation with community-driven safety features.

**Project Location:** `/Users/sylvain/Cursor/Wike_iOS/`
**Reference Project:** `/Users/sylvain/Cursor/popi_biking_fresh/`

---

## Core Requirements

### 1. Technology Stack

**Core Framework:**
- Swift 6
- iOS 14.0+ target
- Xcode 16.0+
- SwiftUI + UIKit hybrid architecture

**Key Dependencies:**
```swift
// Package.swift or Podfile
dependencies: [
    // Maps & Navigation
    .package(url: "https://github.com/mapbox/mapbox-maps-ios", from: "11.0.0"),
    .package(url: "https://github.com/mapbox/mapbox-navigation-ios", from: "3.0.0"),

    // Firebase
    .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.0.0"),
    // - FirebaseCore
    // - FirebaseAuth
    // - FirebaseFirestore
    // - FirebaseCrashlytics

    // Utilities
    .package(url: "https://github.com/Alamofire/Alamofire", from: "5.9.0"), // HTTP networking
]
```

**Architecture:**
- MVVM (Model-View-ViewModel) pattern
- Combine framework for reactive state management
- Protocol-oriented design for testability
- Service layer for API integrations

---

## 2. Feature Scope

### Phase 1: Core 3D Map (Week 1)
**Priority: CRITICAL**

**Features:**
- Mapbox 3D map display with terrain and buildings
- 3 map styles: Streets 3D, Outdoors 3D, Wike 3D (custom cycling style)
- Style switcher in settings
- Camera controls (pan, zoom, tilt, rotate)
- User location display with CoreLocation
- Basic UI shell with navigation bar

**Files to Create:**
```
Wike_iOS/
├── WikeApp.swift                    # SwiftUI App entry point
├── Views/
│   ├── MapView.swift                # Main 3D map view (SwiftUI wrapper)
│   └── MapViewController.swift      # UIKit map controller for Mapbox
├── ViewModels/
│   └── MapViewModel.swift           # Map state management
├── Services/
│   ├── LocationService.swift        # CoreLocation wrapper
│   └── MapboxService.swift          # Mapbox map management
├── Models/
│   └── MapStyle.swift               # Map style enum
└── Config/
    └── APIKeys.swift                # API key configuration
```

**Reference Flutter Files:**
- `../popi_biking_fresh/lib/screens/mapbox_map_screen_simple.dart` (lines 1-200)
- `../popi_biking_fresh/lib/config/api_keys.dart`

---

### Phase 2: Routing & Navigation Engine (Week 2-3)
**Priority: CRITICAL**

#### 2.1 Routing Service (Dual Provider)

**GraphHopper API (PRIMARY):**
- Support 3 cycling profiles: Fastest, Safest, Shortest
- Parse route geometry, distance, duration
- Extract path details: surface type, road class, max speed, lanes
- Handle errors and timeouts

**Mapbox Directions API (SECONDARY):**
- Single cycling profile (balanced)
- Traffic-aware routing
- Used for comparison and backup

**Implementation:**
```swift
enum RoutingProvider {
    case graphHopper
    case mapbox
}

enum CyclingProfile {
    case fastest
    case safest
    case shortest
}

protocol RoutingServiceProtocol {
    func calculateRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        profile: CyclingProfile,
        provider: RoutingProvider
    ) async throws -> Route
}
```

**Files to Create:**
```
Services/
├── RoutingService.swift             # Main routing coordinator
├── GraphHopperService.swift         # GraphHopper API client
├── MapboxDirectionsService.swift    # Mapbox Directions API client
└── RouteParser.swift                # Parse API responses

Models/
├── Route.swift                      # Route model
├── RouteSegment.swift               # Route segment with properties
└── PathDetails.swift                # Surface, road class, etc.
```

**Reference Flutter Files:**
- `../popi_biking_fresh/lib/services/routing_service.dart`
- `../popi_biking_fresh/lib/models/route_result.dart`

#### 2.2 Mapbox Navigation SDK Integration

**IMPORTANT:** Use the **Mapbox Navigation SDK for iOS** instead of building custom turn-by-turn logic. This provides:
- Professional turn-by-turn navigation UI
- Audio instructions
- Lane guidance
- Automatic rerouting
- ETA calculations
- Route progress tracking

**Custom Features to Add:**
1. **Community Warnings** - Overlay route alerts from Firebase
2. **Surface Quality Warnings** - Annotations from GraphHopper surface data
3. **POI Markers** - Display bike parking, shops, etc. along route

**Implementation:**
```swift
import MapboxNavigation

class NavigationViewModel: ObservableObject {
    private var navigationViewController: NavigationViewController?

    func startNavigation(route: Route) {
        // Configure Mapbox Navigation SDK
        let navigationOptions = NavigationOptions(
            styles: [CustomDayStyle()],
            voiceController: customVoiceController
        )

        // Create navigation view controller
        navigationViewController = NavigationViewController(
            for: route.mapboxRoute,
            options: navigationOptions
        )

        // Add custom route alerts (community warnings)
        addCommunityWarnings(to: route)

        // Add surface warnings as annotations
        addSurfaceWarnings(to: route)

        // Present navigation UI
        present(navigationViewController)
    }

    func addCommunityWarnings(to route: Route) {
        // Integrate Firebase community warnings as route alerts
        // See Phase 4 for Firebase integration
    }

    func addSurfaceWarnings(to route: Route) {
        // Parse GraphHopper surface data
        // Create custom annotations on map
    }
}
```

**Files to Create:**
```
ViewModels/
└── NavigationViewModel.swift        # Navigation state & SDK integration

Views/
├── NavigationContainerView.swift    # SwiftUI wrapper for navigation
└── CustomNavigationStyles.swift     # Custom day/night styles

Services/
└── NavigationService.swift          # Navigation SDK wrapper

Models/
├── RouteWarning.swift               # Community + surface warnings
└── ManeuverInstruction.swift        # Turn instructions
```

**Reference Flutter Files:**
- `../popi_biking_fresh/lib/providers/navigation_provider.dart` (736 lines - for logic reference only)
- `../popi_biking_fresh/lib/services/navigation_engine.dart`
- `../popi_biking_fresh/lib/widgets/navigation_card.dart`

**Key Differences from Flutter:**
- ❌ Don't reimplement turn-by-turn logic (use Mapbox SDK)
- ✅ Focus on integrating custom warnings and POIs
- ✅ Customize Navigation SDK UI with your branding

---

### Phase 3: Geocoding & Search (Week 3)
**Priority: HIGH**

#### 3.1 Dual Geocoding Provider

**LocationIQ API (PRIMARY):**
- Forward geocoding: text → coordinates
- Reverse geocoding: coordinates → address
- More affordable, better storage rights
- OSM-based data

**Mapbox Search API (SECONDARY):**
- 160+ data sources
- Smart address matching
- Rich context data
- Batch geocoding (up to 1000)

**Implementation:**
```swift
enum GeocodingProvider {
    case locationIQ
    case mapbox
}

protocol GeocodingServiceProtocol {
    func search(
        query: String,
        provider: GeocodingProvider,
        near: CLLocationCoordinate2D?
    ) async throws -> [SearchResult]

    func reverseGeocode(
        coordinate: CLLocationCoordinate2D,
        provider: GeocodingProvider
    ) async throws -> String
}
```

**Files to Create:**
```
Services/
├── GeocodingService.swift           # Main geocoding coordinator
├── LocationIQService.swift          # LocationIQ API client
└── MapboxSearchService.swift        # Mapbox Search API client

Models/
├── SearchResult.swift               # Search result model
└── PlaceDetails.swift               # Detailed place information

Views/
├── SearchBarView.swift              # Search input UI
├── SearchResultsView.swift          # Results list
└── SearchResultRow.swift            # Individual result
```

**Reference Flutter Files:**
- `../popi_biking_fresh/lib/services/geocoding_service.dart`
- `../popi_biking_fresh/lib/models/search_result.dart`
- `../popi_biking_fresh/lib/widgets/search_bar.dart`

---

### Phase 4: POI & Hazard System (Week 4)
**Priority: HIGH**

#### 4.1 Firebase Integration

**Firebase Collections:**
```
Firestore Structure:
├── cyclingPOIs/                    # Community POIs
│   ├── {poi_id}/
│   │   ├── title: String
│   │   ├── type: String (parking, shop, charging, water, restroom)
│   │   ├── emoji: String
│   │   ├── coordinates: GeoPoint
│   │   ├── createdBy: String (user ID)
│   │   ├── createdAt: Timestamp
│   │   └── geohash: String (for spatial queries)
│
├── communityWarnings/              # Hazard reports
│   ├── {warning_id}/
│   │   ├── title: String
│   │   ├── description: String
│   │   ├── type: String (construction, pothole, traffic, weather, other)
│   │   ├── emoji: String
│   │   ├── coordinates: GeoPoint
│   │   ├── severity: String (low, medium, high)
│   │   ├── createdBy: String
│   │   ├── createdAt: Timestamp
│   │   └── geohash: String
│
└── users/                          # User profiles
    ├── {user_id}/
    │   ├── displayName: String
    │   ├── email: String
    │   ├── photoURL: String?
    │   ├── recentSearches: [String] (max 20)
    │   ├── recentDestinations: [SavedLocation] (max 20)
    │   ├── favoriteLocations: [SavedLocation] (max 20)
    │   └── defaultRouteProfile: String (fastest/safest/shortest)
```

**Implementation:**
```swift
class FirebaseService {
    private let db = Firestore.firestore()

    // POI CRUD
    func fetchPOIs(in bounds: GeoBounds) async throws -> [CyclingPOI]
    func addPOI(_ poi: CyclingPOI) async throws

    // Warning CRUD
    func fetchWarnings(in bounds: GeoBounds) async throws -> [CommunityWarning]
    func reportHazard(_ warning: CommunityWarning) async throws

    // User data
    func saveUserProfile(_ profile: UserProfile) async throws
    func addToFavorites(_ location: SavedLocation) async throws
    func addToSearchHistory(_ query: String) async throws
}
```

**Files to Create:**
```
Services/
├── FirebaseService.swift            # Firestore operations
├── FirebaseAuthService.swift        # Authentication
└── GeohashService.swift             # Spatial queries

Models/
├── CyclingPOI.swift                 # POI model
├── CommunityWarning.swift           # Warning model
├── UserProfile.swift                # User profile
└── SavedLocation.swift              # Favorite/destination

ViewModels/
├── POIViewModel.swift               # POI state management
├── WarningViewModel.swift           # Warning state
└── AuthViewModel.swift              # Authentication state

Views/
├── POIDetailView.swift              # POI detail dialog
├── AddPOIView.swift                 # Add POI form
├── ReportHazardView.swift           # Report hazard form
├── LoginView.swift                  # Login/register screen
└── ProfileView.swift                # User profile screen
```

**Reference Flutter Files:**
- `../popi_biking_fresh/lib/services/firebase_service.dart`
- `../popi_biking_fresh/lib/models/cycling_poi.dart`
- `../popi_biking_fresh/lib/models/community_warning.dart`
- `../popi_biking_fresh/lib/providers/community_provider.dart`

#### 4.2 OSM POI Integration

**Overpass API:**
- Query bike parking, bike shops, charging stations, water, restrooms
- Filter by current map bounds
- Display with emoji markers

**Implementation:**
```swift
class OverpassService {
    func queryPOIs(
        in bounds: GeoBounds,
        types: [POIType]
    ) async throws -> [OSMPOI] {
        // Build Overpass QL query
        // Example: node["amenity"="bicycle_parking"](bbox)
        // Parse JSON response
        // Return POI objects
    }
}
```

**Files to Create:**
```
Services/
└── OverpassService.swift            # OSM POI queries

Models/
└── OSMPOI.swift                     # OSM POI model
```

**Reference Flutter Files:**
- `../popi_biking_fresh/lib/services/osm_poi_service.dart`

#### 4.3 Route Hazard Detection

**Integrate into Navigation:**
1. When route is calculated, detect hazards along route
2. Community warnings from Firebase (spatial query)
3. Surface warnings from GraphHopper path details
4. Merge and sort by distance along route
5. Display as route alerts in Mapbox Navigation SDK

**Implementation:**
```swift
class RouteHazardDetector {
    static func detectHazards(
        on route: Route,
        warnings: [CommunityWarning]
    ) -> [RouteHazard] {
        var hazards: [RouteHazard] = []

        for warning in warnings {
            // Check if warning is within 50m of route
            let closestPoint = route.closestPoint(to: warning.coordinate)
            if closestPoint.distance < 50 {
                let distanceAlongRoute = route.distance(to: closestPoint)
                hazards.append(RouteHazard(
                    warning: warning,
                    distanceAlongRoute: distanceAlongRoute
                ))
            }
        }

        return hazards.sorted { $0.distanceAlongRoute < $1.distanceAlongRoute }
    }
}

class RoadSurfaceAnalyzer {
    static func analyzeSurface(
        pathDetails: [PathDetail],
        route: Route
    ) -> [SurfaceWarning] {
        // Parse GraphHopper surface data
        // Detect poor surfaces (gravel, dirt, cobblestone)
        // Create warnings with emoji and description
    }
}
```

**Files to Create:**
```
Services/
├── RouteHazardDetector.swift        # Detect community warnings on route
└── RoadSurfaceAnalyzer.swift        # Analyze GraphHopper surface data

Models/
├── RouteHazard.swift                # Warning on route
└── SurfaceWarning.swift             # Surface quality warning
```

**Reference Flutter Files:**
- `../popi_biking_fresh/lib/services/route_hazard_detector.dart`
- `../popi_biking_fresh/lib/services/road_surface_analyzer.dart`

---

### Phase 5: Custom Markers & UI (Week 5)
**Priority: MEDIUM**

#### 5.1 Emoji Marker Rendering

Create custom marker images using CoreGraphics/UIKit:

**Marker Types:**
1. **POI Markers** - Circular with emoji (🚲, 🔧, ⚡, 🚰, 🚻)
2. **Warning Markers** - Orange circles with warning emoji (⚠️, 🚧, 🚦, ❄️)
3. **User Location** - Purple dot (snapped position during navigation)
4. **Search Result** - Grey circle with red + symbol
5. **Favorites** - Yellow star (⭐)
6. **Destinations** - Yellow pin (📍)

**Implementation:**
```swift
class MarkerRenderer {
    static func createEmojiMarker(
        emoji: String,
        backgroundColor: UIColor,
        borderColor: UIColor,
        size: CGFloat = 48
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))

        return renderer.image { context in
            // Draw filled circle background
            backgroundColor.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))

            // Draw border
            borderColor.setStroke()
            context.cgContext.strokeEllipse(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))

            // Draw emoji text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.6),
                .foregroundColor: UIColor.black
            ]
            let text = NSAttributedString(string: emoji, attributes: attributes)
            let textSize = text.size()
            let textOrigin = CGPoint(
                x: (size - textSize.width) / 2,
                y: (size - textSize.height) / 2
            )
            text.draw(at: textOrigin)
        }
    }

    static func createPurpleDotMarker(size: CGFloat = 48) -> UIImage {
        // Create purple dot for snapped position
        // Match Flutter design: white circle + purple border + purple center dot
    }
}
```

**Files to Create:**
```
Utilities/
└── MarkerRenderer.swift             # Custom marker image generation

Config/
├── MarkerConfig.swift               # Marker colors and sizes
└── POITypeConfig.swift              # POI emoji mapping
```

**Reference Flutter Files:**
- `../popi_biking_fresh/lib/utils/mapbox_marker_utils.dart`
- `../popi_biking_fresh/lib/config/marker_config.dart`
- `../popi_biking_fresh/lib/config/poi_type_config.dart`

#### 5.2 Navigation UI Customization

**Custom Navigation Card (Overlay on Mapbox Navigation):**
- Current maneuver display
- Distance to next turn
- ETA with range (± 15 min buffer)
- Speed display (current, avg with/without stops)
- Collapsible warnings section (3s auto-collapse)
- Progress bar

**Implementation:**
```swift
struct NavigationCardView: View {
    @ObservedObject var viewModel: NavigationViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Current maneuver
            ManeuverRow(
                instruction: viewModel.nextManeuver,
                distance: viewModel.distanceToManeuver
            )

            // ETA and speed
            StatsRow(
                eta: viewModel.etaRange,
                speed: viewModel.currentSpeed,
                avgSpeed: viewModel.avgSpeed
            )

            // Warnings section (collapsible)
            if viewModel.hasWarnings {
                WarningsSection(
                    warnings: viewModel.routeWarnings,
                    isExpanded: viewModel.warningsExpanded
                )
            }

            // Progress bar
            ProgressBar(
                progress: viewModel.routeProgress
            )
        }
        .padding()
        .background(Color.white.opacity(0.95))
        .cornerRadius(16)
    }
}
```

**Files to Create:**
```
Views/
├── NavigationCardView.swift         # Main navigation card
├── ManeuverRow.swift                # Turn instruction display
├── StatsRow.swift                   # ETA and speed
├── WarningsSection.swift            # Collapsible warnings
├── WarningCard.swift                # Individual warning
├── ProgressBar.swift                # Route progress
└── ArrivalDialog.swift              # Destination arrival dialog
```

**Reference Flutter Files:**
- `../popi_biking_fresh/lib/widgets/navigation_card.dart`
- `../popi_biking_fresh/lib/widgets/warning_card.dart`
- `../popi_biking_fresh/lib/widgets/arrival_dialog.dart`

---

## 3. API Keys Configuration

**Required API Keys:**
```swift
// Config/APIKeys.swift
enum APIKeys {
    static let mapboxAccessToken = "YOUR_MAPBOX_TOKEN"
    static let graphhopperAPIKey = "YOUR_GRAPHHOPPER_KEY"
    static let locationIQAPIKey = "YOUR_LOCATIONIQ_KEY"

    // Optional (for comparison features)
    static let mapboxDirectionsAPIKey = "YOUR_MAPBOX_DIRECTIONS_KEY" // Often same as access token
}
```

**Load from .env file (development) or Info.plist (production):**
```swift
// Load from Info.plist
static var mapboxAccessToken: String {
    guard let token = Bundle.main.infoDictionary?["MAPBOX_ACCESS_TOKEN"] as? String else {
        fatalError("MAPBOX_ACCESS_TOKEN not found in Info.plist")
    }
    return token
}
```

**Reference:**
- See `../popi_biking_fresh/.env.example` for API key list
- See `../popi_biking_fresh/run_ios_device.sh` for how keys are passed

---

## 4. Project Structure

```
Wike_iOS/
├── WikeApp.swift                    # App entry point
├── AppDelegate.swift                # Background location, Firebase init
│
├── Views/                           # SwiftUI Views
│   ├── Map/
│   │   ├── MapView.swift
│   │   ├── MapViewController.swift
│   │   └── MapStylePicker.swift
│   ├── Navigation/
│   │   ├── NavigationContainerView.swift
│   │   ├── NavigationCardView.swift
│   │   ├── ManeuverRow.swift
│   │   ├── WarningsSection.swift
│   │   └── ArrivalDialog.swift
│   ├── Search/
│   │   ├── SearchBarView.swift
│   │   └── SearchResultsView.swift
│   ├── POI/
│   │   ├── POIDetailView.swift
│   │   ├── AddPOIView.swift
│   │   └── POIListView.swift
│   ├── Hazard/
│   │   └── ReportHazardView.swift
│   └── Profile/
│       ├── LoginView.swift
│       ├── ProfileView.swift
│       └── FavoritesView.swift
│
├── ViewModels/                      # MVVM ViewModels
│   ├── MapViewModel.swift
│   ├── NavigationViewModel.swift
│   ├── SearchViewModel.swift
│   ├── POIViewModel.swift
│   ├── WarningViewModel.swift
│   └── AuthViewModel.swift
│
├── Services/                        # API & Business Logic
│   ├── Routing/
│   │   ├── RoutingService.swift
│   │   ├── GraphHopperService.swift
│   │   └── MapboxDirectionsService.swift
│   ├── Geocoding/
│   │   ├── GeocodingService.swift
│   │   ├── LocationIQService.swift
│   │   └── MapboxSearchService.swift
│   ├── POI/
│   │   ├── OverpassService.swift
│   │   └── POIService.swift
│   ├── Navigation/
│   │   ├── NavigationService.swift
│   │   ├── RouteHazardDetector.swift
│   │   └── RoadSurfaceAnalyzer.swift
│   ├── Location/
│   │   └── LocationService.swift
│   ├── Firebase/
│   │   ├── FirebaseService.swift
│   │   └── FirebaseAuthService.swift
│   └── Map/
│       └── MapboxService.swift
│
├── Models/                          # Data Models
│   ├── Route.swift
│   ├── RouteSegment.swift
│   ├── PathDetails.swift
│   ├── CyclingPOI.swift
│   ├── OSMPOI.swift
│   ├── CommunityWarning.swift
│   ├── RouteWarning.swift
│   ├── RouteHazard.swift
│   ├── SearchResult.swift
│   ├── UserProfile.swift
│   ├── SavedLocation.swift
│   └── MapStyle.swift
│
├── Utilities/                       # Helper Classes
│   ├── MarkerRenderer.swift
│   ├── DistanceCalculator.swift
│   ├── GeohashService.swift
│   └── Logger.swift
│
├── Config/                          # Configuration
│   ├── APIKeys.swift
│   ├── MarkerConfig.swift
│   ├── POITypeConfig.swift
│   └── AppColors.swift
│
├── Resources/                       # Assets
│   ├── Assets.xcassets
│   ├── GoogleService-Info.plist
│   └── Info.plist
│
└── Tests/                           # Unit Tests
    ├── RoutingServiceTests.swift
    ├── NavigationViewModelTests.swift
    └── MarkerRendererTests.swift
```

---

## 5. Key Implementation Notes

### 5.1 CoreLocation Best Practices

```swift
class LocationService: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func requestPermissions() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestAlwaysAuthorization()
    }

    func startTracking() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
```

### 5.2 Firebase Authentication

```swift
class FirebaseAuthService {
    func signInWithEmail(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return result.user
    }

    func signInWithGoogle() async throws -> User {
        // Implement Google Sign-In flow
        // See Firebase documentation for iOS
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}
```

### 5.3 Combine Publishers

```swift
class NavigationViewModel: ObservableObject {
    @Published var isNavigating = false
    @Published var currentRoute: Route?
    @Published var routeProgress: Double = 0.0
    @Published var routeWarnings: [RouteWarning] = []

    private var cancellables = Set<AnyCancellable>()

    init(locationService: LocationService) {
        // Subscribe to location updates
        locationService.$currentLocation
            .sink { [weak self] location in
                self?.onLocationUpdate(location)
            }
            .store(in: &cancellables)
    }
}
```

### 5.4 Async/Await for API Calls

```swift
class GraphHopperService {
    private let baseURL = "https://graphhopper.com/api/1"
    private let apiKey = APIKeys.graphhopperAPIKey

    func calculateRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        profile: CyclingProfile
    ) async throws -> Route {
        let url = buildURL(from: from, to: to, profile: profile)

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RoutingError.invalidResponse
        }

        let decodedRoute = try JSONDecoder().decode(GraphHopperResponse.self, from: data)
        return parseRoute(from: decodedRoute)
    }
}
```

---

## 6. Testing Strategy

### 6.1 Unit Tests

**Priority Areas:**
1. Routing service API calls
2. Route hazard detection logic
3. Surface warning analysis
4. Distance calculations
5. Geohash spatial queries

**Example:**
```swift
class RouteHazardDetectorTests: XCTestCase {
    func testDetectHazardsOnRoute() {
        // Given
        let route = createMockRoute()
        let warnings = createMockWarnings()

        // When
        let hazards = RouteHazardDetector.detectHazards(on: route, warnings: warnings)

        // Then
        XCTAssertEqual(hazards.count, 2)
        XCTAssertTrue(hazards[0].distanceAlongRoute < hazards[1].distanceAlongRoute)
    }
}
```

### 6.2 Manual Testing Checklist

**Navigation:**
- [ ] Route calculation works with GraphHopper
- [ ] Route calculation works with Mapbox (fallback)
- [ ] Navigation starts and shows turn instructions
- [ ] Audio instructions play correctly
- [ ] Automatic rerouting when off-route
- [ ] Community warnings appear on route
- [ ] Surface warnings appear on route
- [ ] Arrival dialog shows at destination

**POI System:**
- [ ] OSM POIs load on map
- [ ] Community POIs load from Firebase
- [ ] Can add new POI
- [ ] POI detail view shows correct info
- [ ] POI markers use correct emoji

**Search:**
- [ ] LocationIQ search returns results
- [ ] Mapbox search returns results (comparison)
- [ ] Can select result and navigate to it
- [ ] Search history saves to Firebase

**Authentication:**
- [ ] Email/password login works
- [ ] Google Sign-In works
- [ ] User profile loads correctly
- [ ] Favorites save/load from Firebase

---

## 7. Phased Development Plan

### Week 1: Foundation
- [ ] Create Xcode project
- [ ] Set up dependencies (Mapbox, Firebase, etc.)
- [ ] Implement basic 3D map display
- [ ] Add 3 map styles (Streets, Outdoors, Wike)
- [ ] Implement CoreLocation service
- [ ] Show user location on map

### Week 2: Routing
- [ ] Implement GraphHopper routing service
- [ ] Implement Mapbox Directions service (backup)
- [ ] Add route calculation UI (from/to points)
- [ ] Display route polyline on map
- [ ] Parse path details (surface, road class)

### Week 3: Navigation
- [ ] Integrate Mapbox Navigation SDK
- [ ] Start turn-by-turn navigation
- [ ] Add custom navigation card UI
- [ ] Implement route hazard detection
- [ ] Add surface warning analysis
- [ ] Display warnings on navigation card

### Week 4: POI & Firebase
- [ ] Set up Firebase project
- [ ] Implement Firebase authentication
- [ ] Add login/register UI
- [ ] Implement Firestore POI CRUD
- [ ] Query OSM POIs via Overpass API
- [ ] Display POIs on map with emoji markers
- [ ] Add POI detail view
- [ ] Implement hazard reporting

### Week 5: Search & Polish
- [ ] Implement LocationIQ geocoding
- [ ] Implement Mapbox Search (comparison)
- [ ] Add search bar UI
- [ ] Display search results
- [ ] Add favorites system
- [ ] Implement user profile screen
- [ ] Polish UI/UX
- [ ] Bug fixes and optimization

---

## 8. Critical Success Factors

### Must Have (MVP):
1. ✅ 3D Mapbox map with 3 styles
2. ✅ Route calculation (GraphHopper + Mapbox)
3. ✅ Turn-by-turn navigation (Mapbox SDK)
4. ✅ Community warnings on route
5. ✅ Surface warnings on route
6. ✅ POI display (OSM + Firebase)
7. ✅ Basic search (LocationIQ)
8. ✅ Firebase authentication

### Nice to Have (Post-MVP):
- Mapbox Search comparison
- Advanced statistics (speed averages)
- Offline map caching
- Voice customization
- Social features (friends, leaderboards)

---

## 9. Reference Documentation

### Mapbox Resources:
- **Navigation SDK iOS:** https://docs.mapbox.com/ios/navigation/guides/
- **Maps SDK iOS:** https://docs.mapbox.com/ios/maps/guides/
- **Directions API:** https://docs.mapbox.com/api/navigation/directions/
- **Search API:** https://docs.mapbox.com/api/search/geocoding/

### Firebase Resources:
- **iOS Setup:** https://firebase.google.com/docs/ios/setup
- **Authentication:** https://firebase.google.com/docs/auth/ios/start
- **Firestore:** https://firebase.google.com/docs/firestore/quickstart
- **Google Sign-In:** https://firebase.google.com/docs/auth/ios/google-signin

### Other APIs:
- **GraphHopper API:** https://docs.graphhopper.com/
- **LocationIQ API:** https://locationiq.com/docs
- **Overpass API:** https://wiki.openstreetmap.org/wiki/Overpass_API

### Flutter Reference (for logic):
- See `../popi_biking_fresh/FEATURE_INVENTORY.md` for complete feature list
- See `../popi_biking_fresh/lib/` for all source code reference

---

## 10. Getting Started

### Initial Setup Commands:

```bash
# Navigate to project directory
cd /Users/sylvain/Cursor/Wike_iOS/

# Create Xcode project (if not exists)
# File > New > Project > iOS App
# Name: Wike
# Interface: SwiftUI
# Language: Swift

# Initialize Swift Package Manager
# File > Add Package Dependencies
# Add: mapbox-maps-ios, mapbox-navigation-ios, firebase-ios-sdk

# Create project structure
mkdir -p Views ViewModels Services Models Utilities Config Resources Tests

# Copy Firebase config from Flutter project
cp ../popi_biking_fresh/ios/Runner/GoogleService-Info.plist Resources/

# Create .env file for API keys
touch .env
echo "MAPBOX_ACCESS_TOKEN=your_token_here" >> .env
echo "GRAPHHOPPER_API_KEY=your_key_here" >> .env
echo "LOCATIONIQ_API_KEY=your_key_here" >> .env
```

### First Implementation Task:

**Start with Phase 1: Core 3D Map**

1. Create `MapView.swift` with basic Mapbox map
2. Add style switcher for 3 styles
3. Show user location with CoreLocation
4. Test on device with real GPS

**Expected Output:**
- 3D map showing terrain and buildings
- User location blue dot
- Can switch between Streets/Outdoors/Wike styles
- Smooth pan, zoom, tilt controls

---

## 11. Success Criteria

### Phase 1 Complete:
- [ ] 3D map renders with all 3 styles
- [ ] User location shows on map
- [ ] Camera controls work smoothly
- [ ] No crashes or memory leaks

### Phase 2-3 Complete (Navigation & Search):
- [ ] Can calculate route between two points
- [ ] Turn-by-turn navigation works
- [ ] Community warnings show on route
- [ ] Surface warnings show on route
- [ ] Search works with LocationIQ

### Phase 4 Complete (POI & Firebase):
- [ ] Firebase authentication works
- [ ] Can view POIs on map
- [ ] Can add community POI
- [ ] Can report hazard
- [ ] POIs save to Firebase

### Phase 5 Complete (Polish):
- [ ] Custom navigation UI matches design
- [ ] All markers render correctly
- [ ] Favorites system works
- [ ] Profile screen shows user data
- [ ] App ready for TestFlight

---

## Questions & Clarifications

If you need clarification on any feature:
1. Check `../popi_biking_fresh/FEATURE_INVENTORY.md` for detailed specs
2. Read referenced Flutter files for implementation logic
3. Consult Mapbox/Firebase documentation for iOS-specific APIs
4. Ask for specific examples if needed

---

**Good luck building Wike iOS! 🚴‍♂️**
