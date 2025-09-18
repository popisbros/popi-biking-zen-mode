# Popi Is Biking Zen Mode 🚴‍♂️

A modern Flutter app for urban and suburban cyclists, providing immersive navigation with MapLibre GL, offline GPS tracking, and community-driven safety features.

## Features

### 🗺️ Immersive Navigation
- **MapLibre GL** integration with custom cycling-optimized map styles
- **3D map rendering** with terrain and building extrusion
- **Tilted map view** for better cycling perspective
- **Offline map caching** for uninterrupted navigation

### 📍 Location & Tracking
- **Background GPS tracking** that continues with screen off
- **Offline location services** for areas with poor connectivity
- **Real-time location centering** and route following

### 🚨 Community Features
- **Community warnings** layer for hazards, construction, and alerts
- **Cycling POIs** including bike shops, parking, and repair stations
- **Push notifications** for nearby alerts and updates
- **Warning submission** with location-based reporting

### 🔐 Authentication
- **Multiple sign-in options**: Apple, Google, Facebook, or Email
- **Firebase Authentication** with secure user management
- **User preferences** and personalized settings

### 🎨 Modern Design
- **Zen Mode** interface with minimal UI distractions
- **Custom color palette**: Urban Blue, Moss Green, Signal Yellow, Light Grey
- **Inter font** for clean, modern typography
- **Smooth animations** and intuitive interactions

## Tech Stack

- **Framework**: Flutter 3.24+
- **Maps**: MapLibre GL Flutter plugin
- **State Management**: Riverpod
- **Backend**: Firebase (Auth, Firestore, Cloud Messaging)
- **Storage**: SQLite + Hive for offline caching
- **Location**: Geolocator with background tracking
- **Web Support**: Flutter Web with GitHub Pages deployment

## Getting Started

### Prerequisites
- Flutter SDK 3.24.0 or higher
- Dart SDK 3.5.0 or higher
- Firebase project setup
- MapTiler API key (for map tiles)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/PopiIsBikingZenMode.git
   cd PopiIsBikingZenMode
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   - Create a Firebase project
   - Enable Authentication, Firestore, and Cloud Messaging
   - Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Update `firebase_options.dart` with your project configuration

4. **Configure MapTiler**
   - Get a MapTiler API key from [maptiler.com](https://maptiler.com)
   - Update the API key in `lib/services/map_service.dart`

5. **Run the app**
   ```bash
   flutter run
   ```

### Web Deployment

The app is configured for automatic deployment to GitHub Pages:

1. **Enable GitHub Pages** in your repository settings
2. **Push to main branch** - the GitHub Action will automatically build and deploy
3. **Access your app** at `https://yourusername.github.io/PopiIsBikingZenMode/`

## Project Structure

```
lib/
├── constants/          # App colors, theme, and configuration
├── models/            # Data models (Location, POI, Warning)
├── providers/         # Riverpod state management
├── screens/           # Main app screens
├── services/          # Business logic and API services
├── widgets/           # Reusable UI components
└── utils/             # Utility functions and helpers

assets/
├── fonts/             # Inter font files
├── icons/             # App icons and images
└── map_styles/        # Custom MapLibre styles
```

## Key Components

### Map Screen
- MapLibre GL integration with cycling-optimized styling
- GPS location centering and tracking
- Map controls (zoom, center, tilt)
- Warning report floating action button

### Location Service
- Background GPS tracking
- Permission handling
- Location data streaming
- Distance and bearing calculations

### Firebase Integration
- Multi-provider authentication
- Firestore data management
- Push notification setup
- User preference storage

### Warning System
- Community-driven hazard reporting
- Location-based warning submission
- Real-time warning display
- Severity-based categorization

## Development

### Running Tests
```bash
flutter test
```

### Building for Production
```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

### Code Generation
```bash
# Generate Hive adapters
flutter packages pub run build_runner build
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [MapLibre GL](https://maplibre.org/) for open-source mapping
- [MapTiler](https://maptiler.com/) for map tiles and styling
- [OpenStreetMap](https://www.openstreetmap.org/) for cycling data
- [Firebase](https://firebase.google.com/) for backend services

## Support

For support, email support@popibiking.com or join our community discussions.

---

**Popi Is Biking Zen Mode** - Making urban cycling safer and more enjoyable! 🚴‍♀️✨