# Push & Live Activity Testing — moved to DocC

This index has moved into the SportsCalServer DocC catalog.

**See [`SportsCalAPI/SportsCalServer/Sources/App/Documentation.docc/Articles/ServerOverview.md`](../SportsCalAPI/SportsCalServer/Sources/App/Documentation.docc/Articles/ServerOverview.md)** for the rendered article, or build the docs locally:

```bash
cd SportsCalAPI/SportsCalServer
swift package generate-documentation --target App
open .build/plugins/Swift-DocC/outputs/App.doccarchive
```

The companion articles — push-testing reference, on-device E2E playbook, push-pipeline architecture — are siblings of `ServerOverview.md` in the same DocC catalog.
