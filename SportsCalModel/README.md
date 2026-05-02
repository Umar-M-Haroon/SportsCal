# SportsCalModel

Shared model package consumed by the iOS app, watchOS app, and Vapor server.

Documentation lives in DocC at [`Sources/SportsCalModel/SportsCalModel.docc/`](Sources/SportsCalModel/SportsCalModel.docc/SportsCalModel.md).

## Building the docs

```bash
swift package generate-documentation --target SportsCalModel
open .build/plugins/Swift-DocC/outputs/SportsCalModel.doccarchive
```

Or in Xcode: **Product → Build Documentation** (⌃⇧⌘D), then ⇧⌘0 to open the documentation viewer and pick `SportsCalModel`.
