# WeatherBar

WeatherBar is a macOS menu-bar weather indicator written in Swift. It uses precise macOS Location Services fixes, National Weather Service forecast and station-observation data, and optional Open-Meteo details to show local conditions in the menu bar.

## Features

- National Weather Service API integration with nearest station observations for current conditions.
- Open-Meteo supplemental details and fallback provider support.
- High-accuracy current-location lookup through Core Location, including local display names when available.
- Settings for current/manual location mode and provider selection.
- Background refresh every 20 minutes.
- Retry backoff after failed refreshes.
- Interaction-triggered refresh with a 10-minute cache TTL.
- Custom popover with seven-day forecast lows, highs, precipitation chance, sunrise/sunset, daylight, UV, apparent temperature, precipitation amount, and wind.
- Hover details for hourly temperature, conditions, precipitation chance, UV, humidity, and wind.
- Modular weather-provider interface for swapping data providers.

## Build and Run

```bash
swift test
scripts/build_app_bundle.sh
open .build/WeatherBar.app
```

The app requires macOS location permission on first launch.
