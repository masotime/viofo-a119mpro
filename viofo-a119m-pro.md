# VIOFO A119M Pro Wi-Fi API Notes

Discovery date: 2026-05-10 local time.

Device under test:

- Model/firmware reported by camera: `A119M Pro_V1.1.20260109`
- Camera Wi-Fi SSID: `5G-VIOFO-A119MPro-0489ce`
- Camera IP on dashcam Wi-Fi: `192.168.1.254`
- Mac Wi-Fi interface during testing: `en0`, assigned `192.168.1.22`
- Internet was preserved through iPhone USB: `en7`, default gateway `172.20.10.1`

No Wi-Fi password was recorded in this file or in project files.

## Sources

Local observations are from direct probing of this A119M Pro over its Wi-Fi network.

Public references used for unconfirmed command names and behavior:

- VIOFO A119M Pro product page: https://www.viofo.com/products/viofo-a119m-pro-4k-hdr-voice-control-dash-camera-with-sony-starvis-2-sensor
- VIOFO Station Mode guide: https://www.viofo.com/blogs/viofo-car-dash-camera-guide-faq-and-news/how-to-enable-wi-fi-station-mode-on-your-viofo-dashcam
- DashCamTalk A129 Wi-Fi access thread: https://dashcamtalk.com/forum/threads/how-to-access-the-a129-over-wi-fi-without-the-viofo-app.37279/
- DashCamTalk A329 Wi-Fi API thread with decompiled VIOFO app constants: https://dashcamtalk.com/forum/threads/a329-wifi-api.52469/

The public VIOFO docs confirm browser file access and RTSP live streaming for supported models including the A119M Pro. I did not find an official public SDK. The command names below are mostly from community reverse engineering/decompiled app constants, so model-specific meanings can vary.

## Confirmed Network Services

Confirmed open TCP services on `192.168.1.254`:

| Port | Service | Status | Notes |
| --- | --- | --- | --- |
| `21/tcp` | FTP | Open | Anonymous FTP login was denied with `530`. |
| `23/tcp` | Telnet | Open | Login was not attempted. |
| `80/tcp` | HTTP | Open | File browser and XML API. Server header: `hfs/1.00.000`. |
| `554/tcp` | RTSP | Open | Live video stream. |

Tested but not open in current mode:

| Port | Expected use | Result |
| --- | --- | --- |
| `8192/tcp` | MJPEG stream from VIOFO app constants | Timed out/not listening. |
| `443/tcp` | HTTPS | Timed out/not listening. |
| `8080/tcp` | Alternate HTTP | Timed out/not listening. |
| `8899/tcp` | Unknown/vendor | Timed out/not listening. |

## Confirmed Live Video

Confirmed RTSP endpoints:

```text
rtsp://192.168.1.254/
rtsp://192.168.1.254/xxx.mov
```

The camera API returned the second URL via `cmd=2019`.

`ffprobe` confirmed:

- Container/protocol: RTSP via LIVE555
- Codec: H.264 High profile
- Pixel format: `yuvj420p`
- Resolution: `848x480`
- Frame rate: `30 fps`

One frame capture succeeded during testing, but the temporary frame was removed after discovery.

## Confirmed HTTP File Access

Base file browser:

```text
http://192.168.1.254/
```

Confirmed browsable paths:

```text
http://192.168.1.254/DCIM
http://192.168.1.254/DCIM/Movie/
```

The root listing showed:

- `/DCIM`
- `/CarNo_Backup.txt`
- HTML upload forms for regular and custom upload targets

The `/DCIM` listing showed:

- `/DCIM/Photo`
- `/DCIM/Movie`

The file-list API returned `914` video entries:

- `913` normal entries with attribute `32`
- `1` protected/read-only style entry with attribute `33`

I did not download video files during this discovery pass.

## Confirmed XML API Shape

The camera accepts HTTP RPC-style commands:

```text
http://192.168.1.254/?custom=1&cmd=<command>
http://192.168.1.254/?custom=1&cmd=<command>&par=<value>
http://192.168.1.254/?custom=1&cmd=<command>&str=<string>
```

Responses are XML.

Example response shape:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<Function>
<Cmd>3012</Cmd>
<Status>0</Status>
<String>A119M Pro_V1.1.20260109</String>
</Function>
```

## Confirmed Executed Commands

Only read-only/status commands were intentionally executed.

| Command | Confirmed behavior on this unit | Observed result |
| --- | --- | --- |
| `2019` | Get live-view URL | Returned `rtsp://192.168.1.254/xxx.mov` for movie and photo live view. |
| `3002` | Get supported command list | Returned the supported command IDs listed below. |
| `3012` | Firmware/version | Returned `A119M Pro_V1.1.20260109`. |
| `3014` | Current state/settings snapshot | Returned many command/status pairs. See below. |
| `3015` | File list | Returned XML catalog of SD-card video files. |
| `3016` | Heartbeat/status ping | Returned `Status=0`. |
| `3017` | Card free space | Returned `Value=1309671424` bytes. |
| `3024` | Card status | Returned `Value=1`. |
| `3025` | Firmware/update/filesystem related status | Returned `http://115.29.201.46:8020/download/filedesc.xml`. Meaning not fully confirmed. |
| `9411` | Time zone | Direct `cmd=9411` returns success but not the value. Read the value through `cmd=3014`; write with `cmd=9411&par=<raw>`. |

## Confirmed Timezone Read/Write

The current timezone value is readable from the `cmd=3014` state snapshot:

```xml
<Cmd>9411</Cmd>
<Status>28</Status>
```

Direct read:

```text
http://192.168.1.254/?custom=1&cmd=9411
```

This returns `Status=0`, but did not include the current timezone value on this firmware.

Write:

```text
http://192.168.1.254/?custom=1&cmd=9411&par=<raw>
```

Write behavior was confirmed by:

1. Reading current value `28` from `cmd=3014`.
2. Writing `cmd=9411&par=29`, which returned `Status=0`.
3. Reading `cmd=3014` again and confirming `9411` was `29`.
4. Restoring `cmd=9411&par=28`.
5. Reading `cmd=3014` again and confirming `9411` was restored to `28`.

Observed/raw mapping assumption:

```text
raw value = GMT offset hours + 28
```

Examples:

| Raw | Meaning |
| ---: | --- |
| `28` | GMT/UTC |
| `21` | GMT-7 |
| `20` | GMT-8 |
| `29` | GMT+1 |

The macOS app uses the current macOS UTC offset, including daylight saving time, and writes `9411` using this mapping.

## Confirmed Live Feed Timestamp Limitation

Compared source frames:

- Live RTSP frame: `848x480`
- Recorded MP4 frame: `3840x2160`
- Downscaled recorded MP4 frame: `848x480`

The recorded MP4 bottom-right OSD includes the full date and time:

```text
10/05/2026 19:25:57
```

The live RTSP bottom-right OSD only includes the date:

```text
10/05/2026
```

A downscaled MP4 frame still preserved the full date/time text, so the missing time in live preview is not caused by the app's `scaledToFit` rendering or by simple downscaling. The camera appears to generate a separate live-view OSD that omits the time.

Project-local diagnostic files from this comparison:

```text
/Users/masotime/Documents/Viofo/ViofoA119MPro/diagnostics/live-feed-frame.jpg
/Users/masotime/Documents/Viofo/ViofoA119MPro/diagnostics/sample-movie.mp4
/Users/masotime/Documents/Viofo/ViofoA119MPro/diagnostics/sample-movie-frame.jpg
/Users/masotime/Documents/Viofo/ViofoA119MPro/diagnostics/live-bottom-right.png
/Users/masotime/Documents/Viofo/ViofoA119MPro/diagnostics/movie-bottom-right.png
/Users/masotime/Documents/Viofo/ViofoA119MPro/diagnostics/movie-scaled-bottom-right.png
```

App mitigation: the macOS app always overlays the current instant rendered in the camera's configured timezone while live preview is running. The camera timezone is read from `cmd=3014`. If the camera timezone differs from the macOS timezone, the app prefixes the rendered timestamp/status with `⚠️`.

Important: the overlay is macOS time, not live-read camera time. Direct probes of the date/time commands returned success but no current clock value:

```text
http://192.168.1.254/?custom=1&cmd=3005
http://192.168.1.254/?custom=1&cmd=3006
```

Both returned only:

```xml
<Status>0</Status>
```

Public Novatek-style command notes report date/time writes as:

```text
cmd=3005&str=YYYY-MM-DD
cmd=3006&str=HH:MM:SS
```

The macOS app therefore uses a `Sync Clock` action that writes timezone, date, and time from macOS to the camera. The rendered live timestamp is computed as:

```text
current macOS instant + camera timezone offset from cmd=3014
```

After `Sync Clock`, this should match the camera's intended recording clock. If the timezone later drifts or resets, the app displays `⚠️` because the camera timezone raw value differs from the macOS offset. The camera does not currently provide a confirmed API that continuously reads the live wall-clock value back.

App refresh behavior:

- One top-level `Refresh` action reloads firmware, free space, timezone/state, and `/DCIM/Movie`.
- The same refresh runs automatically every 10 seconds.
- A countdown shows time until the next automatic refresh.
- Manual refresh restarts the countdown.
- Live preview is independent from refresh and should continue until `Stop` is clicked.
- If the RTSP process exits unexpectedly while preview is running, the app attempts to reconnect.

## Confirmed Current State Snapshot

`cmd=3014` returned these raw command/status pairs on this unit:

| Command | Status | Likely meaning when known |
| --- | ---: | --- |
| `1002` | `0` | Capture size |
| `2016` | `1` | Movie recording time |
| `2001` | `1` | Movie record |
| `2002` | `0` | Movie resolution |
| `2003` | `3` | Cyclic recording length |
| `2026` | `2` | Unknown/model-specific |
| `2005` | `6` | Movie exposure |
| `2020` | `50` | Remote control function |
| `2021` | `0` | Unknown/model-specific |
| `2022` | `8000` | Unknown/model-specific |
| `2023` | `0` | Unknown/model-specific |
| `2024` | `0` | Unknown/model-specific |
| `9221` | `1` | Parking motion detection |
| `2007` | `3` | Movie audio |
| `2008` | `1` | Movie date print/stamp |
| `2011` | `1` | G-sensor sensitivity |
| `9220` | `1` | Parking G-sensor or model-specific |
| `2012` | `1` | Auto recording |
| `3007` | `0` | Auto power off |
| `3008` | `2` | Language |
| `3009` | `1` | TV format |
| `3028` | `0` | Live video source |
| `3033` | `0` | Unknown/model-specific |
| `9201` | `0` | Time-lapse recording |
| `9212` | `1` | Movie bitrate |
| `9214` | `1` | GPS info stamp |
| `9216` | `1` | Camera model stamp |
| `9403` | `3` | Unknown/model-specific |
| `9405` | `6` | Screen saver |
| `9406` | `0` | Frequency |
| `9410` | `0` | GPS |
| `9411` | `28` | Time zone |
| `9412` | `0` | Speed unit |
| `9413` | `0` | Unknown/model-specific |
| `9420` | `0` | Unknown/model-specific |
| `9421` | `0` | Parking mode |
| `9424` | `0` | Boot delay |
| `9219` | `0` | Rear camera mirror in some models; likely unused/model-specific here |
| `9222` | `0` | Unknown/model-specific |
| `9428` | `10` | Parking recording timer |
| `9429` | `1` | Unknown/model-specific |
| `9435` | `0` | Unknown/model-specific |
| `9447` | `1` | Unknown/model-specific |
| `9448` | `1` | Unknown/model-specific |
| `9449` | `1` | Unknown/model-specific |
| `9451` | `0` | Unknown/model-specific |
| `9416` | `2` | Unknown/model-specific |
| `9453` | `1` | Voice control |
| `9454` | `0` | Unknown/model-specific |
| `9465` | `0` | Unknown/model-specific |
| `9466` | `0` | Unknown/model-specific |
| `9467` | `0` | Unknown/model-specific |
| `9414` | `1` | Unknown/model-specific |
| `9483` | `0` | Unknown/model-specific |
| `9484` | `0` | Unknown/model-specific |
| `9486` | `1` | Unknown/model-specific |
| `9489` | `0` | Unknown/model-specific |

## Commands Reported Supported By This Unit

`cmd=3002` returned this supported command list:

```text
1001 1002 1003
2016 2017 2018 2019 2025
2001 2002 2003 2026 2027 2028 2005
2020 2021 2022 2023 2024 9221
2007 2008 2009 2011 9220 2012 2013 2014 2015
3001 3002 3003 3004 3005 3006 3007 3008 3009
3010 3011 3012 3013 3014 3015 3016 3017 3018 3019
3021 3022 3023 3024 3025 3026 3028 3029 3030 3031
3032 3033 3034
4001 4002 4005 4003 4004
5001
3037 3038
9201 9212 9214 9216
9403 9405 9406 9407 9408 9410 9411 9412 9413 9417
9420 9421 9422 9423 9424
9219 9222
9426 9427 9428 9429
9435
9446 9447 9448 9449 9450 9451
9416
9453 9454
9465 9466 9467
9414
9483 9484 9486 9488 9489 9490
```

These are "confirmed supported" because the camera reported them, but most were not executed.

## Unconfirmed API Names From Public Reverse Engineering

The following names come from public VIOFO app/decompiled command constants. Some were also present in this camera's supported-command list, but they are unconfirmed unless listed in "Confirmed Executed Commands" above.

Read/status style commands:

| Command | Public name | Notes |
| --- | --- | --- |
| `1002` | `CAPTURE_SIZE` | Present locally. |
| `1003` | `PHOTO_AVAIL_NUM` | Present locally. |
| `2016` | `MOVIE_RECORDING_TIME` | Present locally. |
| `2019` | `LIVE_VIEW_URL` | Confirmed locally. |
| `3012` | `FIRMWARE_VERSION` | Confirmed locally. |
| `3014` | `GET_CURRENT_STATE` | Confirmed locally. |
| `3015` | `GET_FILE_LIST` | Confirmed locally. |
| `3016` | `HEART_BEAT` | Confirmed locally. |
| `3017` | `CARD_FREE_SPACE` | Confirmed locally. |
| `3019` | `GET_BATTERY_LEVEL` | Present locally, not executed. |
| `3024` | `GET_CARD_STATUS` | Confirmed locally. |
| `3025` | `FS_UNKNOW_FORMAT` | Public name conflicts with observed URL-like response; treat as uncertain. |
| `3026` | `GET_UPDATE_FW_PATH` | Present locally, not executed. |
| `3028` | `LIVE_VIDEO_SOURCE` | Present locally; included in current state. |
| `3029` | `GET_WIFI_SSID_PASSWORD` | Present locally, not executed because sensitive. |
| `4001` | `THUMB` | Present locally, not executed. Likely thumbnail retrieval. |
| `4002` | `SCREEN` | Present locally, not executed. Possibly screen/snapshot related. |
| `9426` | `GET_CAR_NUMBER` | Present locally, not executed. |
| `9427` | `GET_CUSTOM_STAMP` | Present locally, not executed. |

State-changing commands:

| Command | Public name | Risk/notes |
| --- | --- | --- |
| `1001` | `PHOTO_CAPTURE` | Present locally. Takes a photo or tries to. |
| `2001` | `MOVIE_RECORD` | Present locally. Start/stop recording. |
| `2002` | `MOVIE_RESOLUTION` | Present locally. Changes video resolution. |
| `2003` | `MOVIE_CYCLIC_REC` | Present locally. Changes loop recording length. |
| `2005` | `MOVIE_EXPOSURE` | Present locally. Changes exposure. |
| `2007` | `MOVIE_AUDIO` | Present locally. Changes audio recording/mic behavior. |
| `2008` | `MOVIE_DATE_PRINT` | Present locally. Changes date stamp. |
| `2009` | `MOVIE_MAX_RECORD_TIME` | Present locally. |
| `2011` | `MOVIE_GSENSOR_SENS` | Present locally. |
| `2012` | `MOVIE_AUTO_RECORDING` | Present locally. |
| `2013` | `MOVIE_REC_BITRATE` | Present locally. |
| `2014` | `LIVE_VIEW_BITRATE` | Present locally. |
| `2015` | `MOVIE_LIVE_VIEW_CONTROL` | Present locally. May affect live view mode. |
| `2017` | `TRIGGER_RAW_ENCODE` | Present locally. Meaning/risk uncertain. |
| `3001` | `CHANGE_MODE` | Present locally. May switch record/photo/settings modes. |
| `3003` | `WIFI_NAME` | Present locally. Changes SSID. |
| `3004` | `WIFI_PWD` | Present locally. Changes Wi-Fi password. |
| `3005` | `SET_DATE` | Present locally. Changes camera date. |
| `3006` | `SET_TIME` | Present locally. Changes camera time. |
| `3007` | `AUTO_POWER_OFF` | Present locally. |
| `3008` | `LANGUAGE` | Present locally. |
| `3009` | `TV_FORMAT` | Present locally. |
| `3010` | `FORMAT_MEMORY` | Present locally. Destructive: formats SD card. |
| `3011` | `RESET_SETTING` | Present locally. Destructive: resets settings. |
| `3018` | `RECONNECT_WIFI` | Present locally. May disrupt connection. |
| `3023` | `REMOVE_LAST_USER` | Present locally. Meaning unclear; could affect pairing/app state. |
| `3032` | `WIFI_STATION_CONFIGURATION` | Present locally. Station-mode configuration. |
| `4003` | `DELETE_ONE_FILE` | Present locally. Destructive. |
| `4004` | `DELETE_ALL_FILE` | Present locally. Destructive. |
| `9201` | `TIME_LAPSE_RECORDING` | Present locally. |
| `9212` | `MOVIE_BITRATE` | Present locally. |
| `9214` | `GPS_INFO_STAMP` | Present locally. |
| `9216` | `CAMERA_MODEL_STAMP` | Present locally. |
| `9220` | `PARKING_G_SENSOR` or model-specific | Present locally. Meaning may conflict across models. |
| `9221` | `PARKING_MOTION_DETECTION` | Present locally. |
| `9405` | `SCREEN_SAVER` | Present locally. |
| `9406` | `FREQUENCY` | Present locally. |
| `9410` | `GPS` | Present locally. |
| `9411` | `TIME_ZONE` | Present locally. |
| `9412` | `SPEED_UNIT` | Present locally. |
| `9417` | `CUSTOM_TEXT_STAMP` | Present locally. |
| `9421` | `PARKING_MODE` | Present locally. |
| `9422` | `CAR_NUMBER` | Present locally. |
| `9424` | `BOOT_DELAY` | Present locally. |
| `9428` | `PARKING_RECORDING_TIMER` | Present locally. |
| `9453` | `VOICE_CONTROL` | Present locally. |

Unconfirmed streams and constants from public sources:

| API | Public source claim | Local result |
| --- | --- | --- |
| `rtsp://192.168.1.254/xxx.mov` | VIOFO app constant `STREAM_VIDEO` | Confirmed by API and RTSP probe. |
| `http://192.168.1.254:8192` | VIOFO app constant `STREAM_MJPEG` | Not open in current mode. May require changing live view mode. |
| `http://192.168.1.254` | VIOFO app constant `BASE_URL` | Confirmed. |
| TCP `3333` | VIOFO app constant `DEFAULT_PORT` | Not confirmed locally. |

## Safety Notes

Treat these as sensitive or destructive and do not run without explicit approval:

- `3010` format SD card
- `3011` reset settings
- `4003` delete one file
- `4004` delete all files
- `3003` change Wi-Fi SSID
- `3004` change Wi-Fi password
- `3029` retrieve Wi-Fi SSID/password
- Any command that changes mode or recording state while the camera is in active use

The camera exposes unauthenticated HTTP/RTSP API access to devices on its Wi-Fi network. Anyone connected to the camera Wi-Fi can likely browse files, stream video, and issue at least some control commands.

## Useful Verified Commands

Read-only checks:

```sh
curl 'http://192.168.1.254/?custom=1&cmd=3012'
curl 'http://192.168.1.254/?custom=1&cmd=3014'
curl 'http://192.168.1.254/?custom=1&cmd=3015'
curl 'http://192.168.1.254/?custom=1&cmd=3016'
curl 'http://192.168.1.254/?custom=1&cmd=3017'
curl 'http://192.168.1.254/?custom=1&cmd=3024'
```

Live stream probe:

```sh
ffprobe -hide_banner -rtsp_transport tcp 'rtsp://192.168.1.254/xxx.mov'
```

HTTP file browsing:

```text
http://192.168.1.254/
http://192.168.1.254/DCIM
http://192.168.1.254/DCIM/Movie/
```
