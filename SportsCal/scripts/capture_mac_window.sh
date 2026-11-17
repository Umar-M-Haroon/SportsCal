#!/bin/zsh
# Captures the frontmost Scoreline window (no OS shadow — the framing script
# adds its own) to a PNG.
#
# Usage: scripts/capture_mac_window.sh out.png [AppName]
# Requires Screen Recording permission for the terminal running it.

set -e
OUT="${1:?usage: capture_mac_window.sh out.png [AppName]}"
APP="${2:-Scoreline}"

WINDOW_ID=$(swift - "$APP" <<'EOF'
import CoreGraphics
import Foundation
let app = CommandLine.arguments[1]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list {
    guard let owner = w[kCGWindowOwnerName as String] as? String, owner == app,
          let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
          let bounds = w[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double, width > 400,
          let id = w[kCGWindowNumber as String] as? Int else { continue }
    print(id)
    break
}
EOF
)

if [[ -z "$WINDOW_ID" ]]; then
  echo "No on-screen $APP window found (is the app running with a main window?)" >&2
  exit 1
fi

# -o: no shadow; -l: window id. Retina displays capture at 2x automatically.
screencapture -o -l "$WINDOW_ID" "$OUT"
echo "captured window $WINDOW_ID -> $OUT ($(sips -g pixelWidth -g pixelHeight "$OUT" | tail -2 | awk '{print $2}' | paste -sd x -))"
