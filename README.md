# solar2d-ironsource

Solar2D self-hosted native plugin for [IronSource (Unity LevelPlay)](https://www.is.com/) SDK **9.2.0**.

Used by [Cubeage/fun-mahjong](https://github.com/Cubeage/fun-mahjong).

---

## Integration

### build.settings

```lua
plugins = {
    ["plugin.ironSource"] = {
        publisherId = "com.cubeage",
        supportedPlatforms = {
            android = { url = "https://github.com/Cubeage/solar2d-ironsource/releases/download/v9.2.0/android.tgz" },
            iphone  = { url = "https://github.com/Cubeage/solar2d-ironsource/releases/download/v9.2.0/iphone.tgz" },
            ["mac-sim"]  = false,
            ["win32-sim"] = false,
        },
    },
},
```

> Android `minSdkVersion` must be **21** or higher.  
> iOS `MinimumOSVersion` must be **"12"** or higher.

---

## Lua API

```lua
local ironSource = require("plugin.ironSource")

-- Initialize
ironSource.init(listener, {
    key            = "YOUR_APP_KEY",   -- required
    userId         = "user_123",
    hasUserConsent = true,
    coppaUnderAge  = false,
    ccpaDoNotSell  = false,
    showDebugLog   = false,
    attStatus      = "authorized",     -- iOS ATT status
    isAutoLoad     = true,
})

-- Load an ad
ironSource.load("interstitial")
-- rewardedVideo is auto-loaded by the IronSource SDK

-- Show an ad
ironSource.show("interstitial", { placementName = "MyPlacement" })
ironSource.show("rewardedVideo")

-- Check availability
local ready = ironSource.isAvailable("interstitial")
local avail = ironSource.isAvailable("rewardedVideo")
```

### Events dispatched to the listener

| name | type | phase | isError |
|------|------|-------|---------|
| ironSource | interstitial | loaded | false |
| ironSource | interstitial | closed | false |
| ironSource | interstitial | show | false / true |
| ironSource | rewardedVideo | available | false |
| ironSource | rewardedVideo | reward | false |
| ironSource | rewardedVideo | closed | false |
| ironSource | rewardedVideo | show | false / true |

---

## Building from source

### Android

Requires Java 17 and the Gradle wrapper (`./gradlew`).

```bash
cd android
# Place Corona.jar from Solar2D SDK in android/libs/
./gradlew assembleRelease
# Output: android/build/outputs/aar/plugin-release.aar
```

Package:
```bash
mkdir pkg && cp android/build/outputs/aar/*-release.aar pkg/plugin-release.aar
cp android/corona.gradle pkg/ && cp metadata.lua pkg/
cd pkg && tar czf ../android.tgz .
```

### iOS

Requires Xcode on macOS with IronSource iOS SDK XCFramework and Solar2D Corona headers.

```bash
cd ios
# Set CORONA_ROOT and IRONSOURCE_ROOT
make
# Output: ios/libplugin_ironSource.a
```

Package:
```bash
mkdir pkg && cp ios/libplugin_ironSource.a pkg/
cp metadata.lua pkg/
cp -r path/to/IronSource.xcframework pkg/Frameworks/
cd pkg && tar czf ../iphone.tgz .
```

---

## License

MIT — see [LICENSE](LICENSE).
