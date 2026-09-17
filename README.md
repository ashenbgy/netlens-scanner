# Alpha NetScope

Alpha NetScope is an on-device Android Wi-Fi signal meter. It monitors the connected network's signal strength every second (with session min/avg/max, link speed and Wi-Fi standard), charts RSSI over the last three minutes, shows a channel-usage graph and list of nearby access points per band, and flags channel congestion for the network you are on.

## Privacy and permissions

- Connected Wi-Fi RSSI monitoring needs only Wi-Fi access.
- The screen stays on while the app is in the foreground so readings continue while you walk around.
- Android may require Location permission and Location services for nearby access-point scans.
- Readings are kept in memory only while the app is open; nothing is persisted except the onboarding flag and local crash diagnostics.
- Nothing leaves the device unless the user explicitly shares a diagnostic report.

See [PRIVACY.md](PRIVACY.md) for the complete privacy policy.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk
```

The Android application identifier is `app.alphanetscope`.
