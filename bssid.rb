class Bssid < Formula
  desc "Scan Wi-Fi networks and connect to a specific access point on macOS"
  homepage "https://github.com/braineo/airport-bssid"
  license "GPL-3.0-only"
  head "https://github.com/braineo/airport-bssid.git", branch: "master"

  depends_on xcode: ["12.0", :build]
  depends_on :macos

  # Location authorization and app packaging, based on upstream 6cae7a79.
  patch :DATA

  def install
    system "swift", "build",
           "--configuration", "release",
           "--disable-sandbox",
           "-Xlinker", "-sectcreate",
           "-Xlinker", "__TEXT",
           "-Xlinker", "__info_plist",
           "-Xlinker", buildpath/"packaging/Info.plist"

    app = libexec/"BSSID.app"
    (app/"Contents/MacOS").install ".build/release/bssid"
    (app/"Contents").install "packaging/Info.plist"
    libexec.install "packaging/sign-app.sh"

    # Use the stable opt path, including after a HEAD upgrade.
    (bin/"bssid").write <<~SH
      #!/bin/bash
      exec "#{opt_libexec}/BSSID.app/Contents/MacOS/bssid" "$@"
    SH
    (bin/"bssid-sign").write <<~SH
      #!/bin/bash
      exec /bin/bash "#{opt_libexec}/sign-app.sh" "#{opt_libexec}/BSSID.app"
    SH
    (bin/"bssid-authorize").write <<~SH
      #!/bin/bash
      exec /usr/bin/open -W "#{opt_libexec}/BSSID.app" --args --authorize
    SH
    chmod 0755, [bin/"bssid", bin/"bssid-sign", bin/"bssid-authorize"]
  end

  def caveats
    <<~EOS
      Run these commands in your normal terminal after installation or upgrade:
        bssid-sign
        bssid-authorize

      bssid-sign uses SIGN_ID if set, or the sole valid code-signing identity.
      With zero or multiple identities it exits without changing the signature.
      Your keychain may ask permission to use the signing key.

      Allow BSSID to access Location Services when prompted, then run:
        bssid scan

      Signing happens outside Homebrew's build sandbox and after binary fixups.
      Location authorization and Wi-Fi identifier access depend on macOS policy.
    EOS
  end

  test do
    output = shell_output("#{bin}/bssid --help")
    assert_match "scan", output
    assert_match "connect", output
  end
end

__END__
diff --git a/Sources/bssid/LocationAuthorization.swift b/Sources/bssid/LocationAuthorization.swift
new file mode 100644
index 0000000..18a51ae
--- /dev/null
+++ b/Sources/bssid/LocationAuthorization.swift
@@ -0,0 +1,58 @@
+import AppKit
+import CoreLocation
+import Foundation
+
+final class LocationAuthorization: NSObject, CLLocationManagerDelegate {
+    private let manager = CLLocationManager()
+
+    override init() {
+        super.init()
+        manager.delegate = self
+    }
+
+    var status: CLAuthorizationStatus {
+        return manager.authorizationStatus
+    }
+
+    var isAuthorized: Bool {
+        return status == .authorizedAlways
+    }
+
+    func requireAuthorization() -> Bool {
+        guard CLLocationManager.locationServicesEnabled() else {
+            report("Location Services is disabled. Enable it in System Settings > Privacy & Security > Location Services.")
+            return false
+        }
+        if isAuthorized { return true }
+        guard status == .notDetermined else {
+            report("Location access is denied or restricted. Enable BSSID in System Settings > Privacy & Security > Location Services.")
+            return false
+        }
+        guard Bundle.main.object(forInfoDictionaryKey: "NSLocationUsageDescription") != nil else {
+            report("Missing location usage description. Build and run the packaged BSSID.app.")
+            return false
+        }
+
+        // Keep the manager alive and service its delegate on the main run loop.
+        let app = NSApplication.shared
+        app.setActivationPolicy(.accessory)
+        app.activate(ignoringOtherApps: true)
+        manager.requestAlwaysAuthorization()
+        let deadline = Date().addingTimeInterval(60)
+        while status == .notDetermined && Date() < deadline {
+            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
+        }
+        guard isAuthorized else {
+            report("Location access was not granted (or the request timed out). Run BSSID.app with --authorize to retry.")
+            return false
+        }
+        return true
+    }
+
+    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
+    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {}
+
+    private func report(_ message: String) {
+        FileHandle.standardError.write(Data((message + "\n").utf8))
+    }
+}
diff --git a/Sources/bssid/main.swift b/Sources/bssid/main.swift
index a383aa0..6f67d5d 100644
--- a/Sources/bssid/main.swift
+++ b/Sources/bssid/main.swift
@@ -1,9 +1,19 @@
 import Guaka
-import CoreLocation
+import Foundation
 
-setupCommands()
-let locationManager = CLLocationManager()
-if #available(macOS 10.15, *) {
-    locationManager.requestAlwaysAuthorization()
+let arguments = Array(CommandLine.arguments.dropFirst())
+let authorization = LocationAuthorization()
+if arguments == ["--location-status"] {
+    print("Location authorization: \(authorization.status.rawValue); authorized: \(authorization.isAuthorized)")
+    exit(0)
+}
+if arguments == ["--authorize"] || arguments.isEmpty {
+    exit(authorization.requireAuthorization() ? 0 : 1)
 }
+let needsLocation = ["scan", "connect", "connect-ssid"].contains(arguments.first ?? "")
+let showingHelp = arguments.contains("--help") || arguments.contains("-h")
+if needsLocation && !showingHelp && !authorization.requireAuthorization() {
+    exit(1)
+}
+setupCommands()
 rootCommand.execute()
diff --git a/packaging/Info.plist b/packaging/Info.plist
new file mode 100644
index 0000000..46ff4be
--- /dev/null
+++ b/packaging/Info.plist
@@ -0,0 +1,15 @@
+<?xml version="1.0" encoding="UTF-8"?>
+<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
+<plist version="1.0"><dict>
+<key>CFBundleIdentifier</key><string>it.gmerlino.bssid</string>
+<key>CFBundleName</key><string>BSSID</string>
+<key>CFBundleDisplayName</key><string>BSSID</string>
+<key>CFBundleExecutable</key><string>bssid</string>
+<key>CFBundlePackageType</key><string>APPL</string>
+<key>CFBundleVersion</key><string>1</string>
+<key>CFBundleShortVersionString</key><string>1.0</string>
+<key>LSMinimumSystemVersion</key><string>12.0</string>
+<key>LSUIElement</key><true/>
+<key>NSLocationUsageDescription</key><string>BSSID needs location permission to display nearby Wi-Fi network names and access point addresses.</string>
+<key>NSLocationWhenInUseUsageDescription</key><string>BSSID needs location permission to display nearby Wi-Fi network names and access point addresses.</string>
+</dict></plist>
diff --git a/packaging/sign-app.sh b/packaging/sign-app.sh
new file mode 100755
index 0000000..f6e19b5
--- /dev/null
+++ b/packaging/sign-app.sh
@@ -0,0 +1,18 @@
+#!/bin/bash
+set -euo pipefail
+APP="${1:?Usage: sign-app.sh /path/to/BSSID.app}"
+IDENTITY="${SIGN_ID:-}"
+if [[ -z "$IDENTITY" ]]; then
+  IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/awk '/^[[:space:]]*[0-9]+\)/ && length($2)==40 {print $2}' | /usr/bin/sort -u)"
+  COUNT="$(printf '%s\n' "$IDENTITIES" | /usr/bin/awk 'NF {n++} END {print n+0}')"
+  if [[ "$COUNT" != 1 ]]; then
+    printf 'Found %s identities. Set SIGN_ID to the intended certificate fingerprint.\n' "$COUNT" >&2
+    exit 1
+  fi
+  IDENTITY="$IDENTITIES"
+fi
+# File Provider folders can carry Finder metadata rejected by codesign.
+/usr/bin/xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
+/usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
+/usr/bin/codesign --verify --strict --verbose=2 "$APP"
+/usr/bin/codesign --display --verbose=2 "$APP" 2>&1
