# solar2d-ironsource

<p align="center"><img src="https://mark.sylphx.com/api/v1/mark/hero.svg?type=aurora&color=0:A02028,50:E03840,100:1A1A1A&text=solar2d-ironsource&desc=Solar2D%20ironSource%20plugin%20%28superseded%29" alt="solar2d-ironsource" /></p>

> **Superseded (2026-09-26, owner decision, SylphxAI/owner#704).** Cubeage is
> IAP-first, with light ads or none. Where a title keeps ads, they come only from
> AdMob (Google Mobile Ads Next-Gen SDK, no mediation layer), by default opt-in
> rewarded ads plus a remove-ads purchase. ironSource / Unity LevelPlay, Unity Ads,
> Meta, Mintegral, Pangle and every other network are retired. In-flight SDK 4.2.x
> builds may ship as they are; nothing new goes into LevelPlay, and each title
> moves to AdMob-only or no ads at its next build. This plugin is kept only so the
> in-flight Fun Mahjong 4.2.x build can ship and be patched; no new title uses
> it, and it is archived once no live build needs it.

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
| ironSource | load / show | failed | true |

Every event carries `name`, `type`, `phase` and `isError`. `response` carries the SDK
message when there is one (for example error text) and is omitted otherwise, so the Lua
field is `nil`. Event dispatch failures are logged by the plugin and never crash the app.

An unknown `adUnitType` passed to `ironSource.load()` or `ironSource.show()` now also
reports `type = "load"` / `"show"`, `phase = "failed"`, `isError = true` and a
`response` naming the rejected value, instead of failing silently in the log.

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
