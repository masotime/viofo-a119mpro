# VIOFO A119M Pro macOS App

Native macOS utility for a VIOFO A119M Pro connected over the camera's Wi-Fi network.

This repository contains the macOS app in `ViofoA119MPro/` and the camera API discovery notes in `viofo-a119m-pro.md`.

The app uses only local camera endpoints:

- HTTP/XML API on `http://192.168.1.254`
- RTSP live stream on `rtsp://192.168.1.254/xxx.mov`
- HTTP file downloads from `/DCIM/Movie`

It does not require an active internet connection.

## Capabilities

Confirmed against this camera/firmware:

- Camera firmware: `A119M Pro_V1.1.20260109`
- Camera address on VIOFO Wi-Fi: `192.168.1.254`
- HTTP/XML API: `http://192.168.1.254/?custom=1&cmd=<command>`
- HTTP file browser: `http://192.168.1.254/`
- Movie folder access: `http://192.168.1.254/DCIM/Movie/`
- RTSP live stream: `rtsp://192.168.1.254/xxx.mov`
- Live stream format: H.264, `848x480`, 30 fps
- Free-space API: `cmd=3017`
- File-list API: `cmd=3015`
- Firmware API: `cmd=3012`
- State snapshot API: `cmd=3014`
- Timezone setting: read from `cmd=3014`, write with `cmd=9411&par=<raw>`

Open services observed on the camera:

| Port | Service | Use |
| --- | --- | --- |
| `21/tcp` | FTP | Open, but anonymous login was denied. Not used by this app. |
| `23/tcp` | Telnet | Open. Not used by this app. |
| `80/tcp` | HTTP | XML API, file list, file downloads. |
| `554/tcp` | RTSP | Live video preview. |

Not observed as available in the current camera mode:

- `http://192.168.1.254:8192` MJPEG stream
- HTTPS on `443`
- Alternate HTTP on `8080`

## App Features

- Shows live camera preview.
- Always renders a camera-timezone-adjusted timestamp over the live preview because the camera's RTSP live-view OSD only includes the date.
- Shows a `⚠️` warning in the timestamp/status area when the camera timezone does not match macOS.
- Loads only `/DCIM/Movie` entries.
- Downloads selected movie files.
- Downloads all movie files.
- Selects movie files by clicking rows or using keyboard navigation.
- Sorts the file viewer by clicking the Name, Size, Time, or Folder column headers; clicking the active header reverses the sort order.
- Lets the user choose the local download folder.
- Reports SD-card free space.
- Reads camera timezone.
- Shows current macOS timezone.
- Syncs the camera timezone, date, and time to macOS using `cmd=9411`, `cmd=3005`, and `cmd=3006`.
- Uses one top-level `Refresh` action for status, timezone, free space, and file list.
- Automatically refreshes every 10 seconds and shows a countdown to the next refresh.
- Uses local network only; no internet access is needed.

## Intentionally Excluded Controls

The camera reports support for many additional commands, but this app does not expose risky controls:

- Format SD card: `cmd=3010`
- Reset camera settings: `cmd=3011`
- Delete one/all files: `cmd=4003`, `cmd=4004`
- Change Wi-Fi SSID/password: `cmd=3003`, `cmd=3004`
- Retrieve Wi-Fi SSID/password: `cmd=3029`
- Start/stop recording: `cmd=2001`
- Change resolution, exposure, audio, parking mode, stamps, GPS, or other recording settings

The full discovery log is in:

```text
/Users/masotime/Documents/Viofo/viofo-a119m-pro.md
```

## Build

```sh
cd /Users/masotime/Documents/Viofo/ViofoA119MPro
./build_app.sh
```

The app bundle is created at:

```text
/Users/masotime/Documents/Viofo/ViofoA119MPro/build/VIOFO A119M Pro.app
```

## Runtime Dependencies

HTTP API calls and downloads use macOS's built-in `/usr/bin/curl`.

Live RTSP preview uses a local `ffmpeg` executable. The app checks common Homebrew/MacPorts paths, including:

- `/opt/homebrew/bin/ffmpeg`
- `/usr/local/bin/ffmpeg`
- `/opt/local/bin/ffmpeg`

File browsing, downloads, free-space reporting, and timezone sync do not need `ffmpeg`.

## Timezone Mapping

The camera reports timezone through `cmd=9411` inside the `cmd=3014` state snapshot.

Observed raw mapping assumption:

```text
raw value = GMT offset hours + 28
```

So:

- `28` = GMT/UTC
- `21` = GMT-7
- `20` = GMT-8

The app's "Sync Clock" button uses the current macOS UTC offset, including daylight saving time, then writes `cmd=9411&par=<raw>`.

It also writes the current macOS local date and time to the camera:

```text
cmd=3005&str=YYYY-MM-DD
cmd=3006&str=HH:MM:SS
```

Direct read probes for `cmd=3005` and `cmd=3006` returned `Status=0` but did not include a wall-clock value on this firmware. That means the app can write/sync the camera clock, but it cannot prove the live camera clock continuously by reading it back from an API.

## Live Feed Timestamp Limitation

The recorded 4K MP4 files include the full bottom-right timestamp, for example:

```text
10/05/2026 19:25:57
```

The RTSP live feed from the camera is a separate `848x480` stream. Captured live frames show only the date at the bottom-right; the time is absent in the source RTSP frame before the app displays it. A downscaled MP4 frame still preserves the time, so this is camera-side live-view OSD behavior, not app cropping.

Mitigation: the app always overlays the current instant rendered in the camera's configured timezone. The camera timezone is read from `cmd=3014`; if it differs from the macOS timezone, the app prefixes the rendered timestamp/status with `⚠️` so the mismatch is obvious. `Sync Clock` writes timezone, date, and time from macOS to the camera.

The camera does not currently provide a confirmed API for continuously reading its wall-clock value, so the overlay is computed as:

```text
current macOS instant + camera timezone offset from cmd=3014
```

This avoids hiding timezone mismatches: if the camera timezone is wrong, the rendered timestamp is also visibly wrong and marked with `⚠️`.

## Refresh Behavior

The top `Refresh` button reloads everything except the live feed:

- firmware
- free space
- timezone/state snapshot
- `/DCIM/Movie` file list

The app automatically performs the same refresh every 10 seconds. The countdown next to `Refresh` shows the next scheduled refresh; clicking `Refresh` runs it immediately and restarts the countdown. Live preview is managed separately and should continue until `Stop` is clicked. If the RTSP process exits unexpectedly, the app attempts to reconnect while the preview is still in the running state.
