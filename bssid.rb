class Bssid < Formula
  desc "Scan Wi-Fi networks and connect to a specific access point on macOS"
  homepage "https://github.com/braineo/airport-bssid"
  license "GPL-3.0-only"
  head "https://github.com/braineo/airport-bssid.git", branch: "master"

  depends_on xcode: ["11.4", :build]
  depends_on :macos

  def install
    system "swift", "build",
           "--configuration", "release",
           "--disable-sandbox"

    bin.install ".build/release/bssid"
  end

  def caveats
    <<~EOS
      BSSID requires your Developer Signing Identity, which can be found by issuing the following command on the CLI:
        security find-identity -v -p codesigning
      in order to provide entitlements to the binary (hard requirement for Catalina).
      The Identity may be set as an environment variable as follows:
        HOMEBREW_NO_ENV_FILTERING=1 SIGN_ID="abcdef123456" brew install bssid
    EOS
  end

  test do
    output = shell_output("#{bin}/bssid --help")
    assert_match "scan", output
    assert_match "connect", output
  end
end
