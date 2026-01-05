# BT Shark 🦈

The apex predator of the WiFi Pineapple fish army. Equipped with electroreception (RSSI sensing), it hunts Bluetooth prey through murky RF waters. No MAC rotation can hide you.

## Features

- **BLE RSSI Tracking**: Passive tracking via btmon - no pairing required
- **MAC Rotation Detection**: Tracks by device name, detects when MAC changes
- **Geiger-Style Feedback**: Audio clicks speed up as you get closer
- **10-Level Signal Bar**: Fine-grained 5dB steps from -35 to -85 dBm
- **Auto Adapter Reset**: Cleans up orphan processes and resets hci0
- **Watchdog**: Restarts lescan if it dies

## Signal Strength

| RSSI      | Bar          | Feedback |
|-----------|--------------|----------|
| > -35 dBm | ██████████   | Vibrate + High tone |
| -45 dBm   | ████████░░   | High tone |
| -55 dBm   | ██████░░░░   | Medium tone |
| -65 dBm   | ████░░░░░░   | Low tone |
| -75 dBm   | ██░░░░░░░░   | Low tone |
| < -85 dBm | ░░░░░░░░░░   | Listening... |

## Usage

1. Run payload from Payloads menu
2. Wait for 30 second BLE scan
3. Select target device by number
4. Walk around - clicks speed up as you approach!
5. Press B to stop

## Loot

Scan results saved to `/root/loot/bluetooth/`

## Author

Trout

## Version

1.0.4
