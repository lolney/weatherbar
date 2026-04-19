# WeatherBar

WeatherBar is a macOS menu-bar weather indicator written in Swift. It uses macOS Location Services to fetch local National Weather Service forecast data, then shows the current temperature and condition in the menu bar.

## Features

- National Weather Service API integration.
- Current-location lookup through Core Location.
- Background refresh every 20 minutes.
- Interaction-triggered refresh with a 10-minute cache TTL.
- Seven-day forecast menu with lows, highs, and precipitation chance.
- Hourly forecast submenus with temperature, conditions, precipitation chance, and wind.
- Modular weather-provider interface for swapping data providers.

## Build and Run

```bash
swift test
scripts/build_app_bundle.sh
open .build/WeatherBar.app
```

The app requires macOS location permission on first launch.
