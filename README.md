# Popi Is Biking Zen Mode 🚴‍♂️

**V1.0 RELEASE** - A comprehensive Flutter-based cycling companion app with immersive navigation, community features, and intelligent GPS tracking.

[![Flutter](https://img.shields.io/badge/Flutter-3.35.4-blue.svg)](https://flutter.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-Enabled-orange.svg)](https://firebase.google.com/)
[![GitHub Pages](https://img.shields.io/badge/Deployed-GitHub%20Pages-green.svg)](https://popisbros.github.io/popi-biking-zen-mode/)

## 🎉 V1.0 Features

### 🗺️ Core Map Features
- ✅ **Interactive Map** with Flutter Map (Leaflet-based for web compatibility)
- ✅ **Multiple Map Styles**: Cycling, OpenStreetMap, Satellite
- ✅ **Custom Teardrop Pin Markers** (1px from top positioning)
- ✅ **Real-time GPS Location Tracking** with Auto-Centering
- ✅ **Smart GPS Movement Detection** (50m threshold with original reference tracking)
- ✅ **Zoom Controls** and Map Style Selector
- ✅ **Long-press Context Menu** (Add POI, Report Hazard)

### 📍 POI & Hazard Management
- ✅ **Community POI Creation, Editing, and Deletion**
- ✅ **Community Hazard/Warning Reporting, Editing, and Deletion**
- ✅ **OSM POI Integration** with Overpass API
- ✅ **Bounds-based Loading** for Efficient Data Management
- ✅ **Smart Reload Logic** with Extended Bounds (3x3 area)
- ✅ **Background Data Loading** with Seamless Transitions
- ✅ **Type-specific Icons** and Teardrop Pin Styling

### 🎨 UI/UX Features
- ✅ **Modern Design** with Custom Color Palette (Urban Blue, Moss Green, Signal Yellow, Azure Blue)
- ✅ **Inter Font Integration** via Google Fonts
- ✅ **Responsive Design** for Web and Mobile
- ✅ **Accessibility Features** (Semantics, Tooltips)
- ✅ **Debug Panel** with Comprehensive Data Display
- ✅ **Status Indicators** for GPS, POI, Hazard, and OSM POI Counts
- ✅ **Smooth Animations** and Transitions

### 🔧 Technical Features
- ✅ **Flutter Web Deployment** via GitHub Pages
- ✅ **Firebase Integration** (Auth, Firestore, Cloud Messaging)
- ✅ **Riverpod State Management**
- ✅ **Offline GPS Tracking** with Geolocator
- ✅ **Smart Bounds-based Data Loading**
- ✅ **Background Data Preservation** During Reloads
- ✅ **CORS Configuration** for Firebase
- ✅ **Environment Variables** for API Keys
- ✅ **GitHub Actions CI/CD Pipeline**

## 🚀 Live Demo

**Try the app**: [https://popisbros.github.io/popi-biking-zen-mode/](https://popisbros.github.io/popi-biking-zen-mode/)

## 🛠️ Tech Stack

- **Framework**: Flutter 3.35.4
- **Maps**: Flutter Map (Leaflet-based)
- **State Management**: Riverpod
- **Backend**: Firebase (Auth, Firestore, Cloud Messaging)
- **Location**: Geolocator for GPS tracking
- **OSM Data**: Overpass API integration
- **Deployment**: GitHub Pages + GitHub Actions
- **Fonts**: Inter via Google Fonts

## 📋 Prerequisites

- Flutter SDK 3.35.4 or higher
- Dart SDK 3.9.2 or higher
- Firebase project setup
- Thunderforest API key (for cycling maps)
- MapTiler API key (for satellite maps)

## 🚀 Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/popisbros/popi-biking-zen-mode.git
cd popi-biking-zen-mode
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Configure Environment Variables
Create a `.env` file in the root directory:
```env
THUNDERFOREST_API_KEY=your_thunderforest_api_key
MAPTILER_API_KEY=your_maptiler_api_key
```

### 4. Configure Firebase
- Create a Firebase project
- Enable Authentication, Firestore, and Cloud Messaging
- Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
- Update `lib/firebase_options.dart` with your project configuration

### 5. Run the App
```bash
# Web
flutter run -d chrome

# Mobile
flutter run
```

## 🌐 Web Deployment

The app is configured for automatic deployment to GitHub Pages:

1. **Enable GitHub Pages** in your repository settings
2. **Set up GitHub Secrets**:
   - `THUNDERFOREST_API_KEY`: Your Thunderforest API key
   - `MAPTILER_API_KEY`: Your MapTiler API key
3. **Push to main branch** - GitHub Actions will automatically build and deploy
4. **Access your app** at `https://yourusername.github.io/popi-biking-zen-mode/`

## 📁 Project Structure

```
lib/
├── constants/          # App colors, theme, and configuration
├── models/            # Data models (Location, POI, Warning, OSM POI)
├── providers/         # Riverpod state management
├── screens/           # Main app screens (Map, POI Management, Hazard Reporting)
├── services/          # Business logic and API services
├── widgets/           # Reusable UI components
└── utils/             # Utility functions and helpers

assets/
├── fonts/             # Inter font files
└── icons/             # App icons and images
```

## 🔧 Key Components

### Map Screen (`lib/screens/map_screen.dart`)
- Interactive map with Flutter Map
- GPS location tracking and auto-centering
- POI and hazard markers with teardrop pins
- Map controls and style selector
- Long-press context menu

### Location Service (`lib/services/location_service.dart`)
- GPS tracking with Geolocator
- Permission handling
- Location data streaming
- Distance calculations

### Firebase Integration (`lib/services/firebase_service.dart`)
- Firestore data management
- Authentication setup
- Community POI and hazard management
- Bounds-based queries

### OSM Integration (`lib/services/osm_service.dart`)
- Overpass API integration
- POI data fetching
- Bounds-based OSM queries
- Type-specific POI filtering

## 🧪 Development

### Running Tests
```bash
flutter test
```

### Building for Production
```bash
# Web
flutter build web --release

# Android
flutter build apk --release

# iOS
flutter build ios --release
```

### Debug Features
- **Debug Panel**: Access via debug button (top-left)
- **OSM Debug Window**: Shows API calls and responses
- **Console Logging**: Comprehensive logging for development
- **Visual Indicators**: Status indicators for all data types

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Flutter Map](https://github.com/fleaflet/flutter_map) for web-compatible mapping
- [Thunderforest](https://www.thunderforest.com/) for cycling map tiles
- [MapTiler](https://maptiler.com/) for satellite map tiles
- [OpenStreetMap](https://www.openstreetmap.org/) for POI data
- [Firebase](https://firebase.google.com/) for backend services
- [Overpass API](https://overpass-api.de/) for OSM data queries

## 📞 Support

For support, create an issue in the GitHub repository or contact the development team.

---

**Popi Is Biking Zen Mode V1.0** - Making urban cycling safer and more enjoyable! 🚴‍♀️✨

*Ready for production use with comprehensive features and robust architecture.*