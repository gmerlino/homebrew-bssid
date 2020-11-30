class Bssid < Formula
  desc "command line tool to connect to specific bssid for macOS"
  homepage "https://github.com/braineo/airport-bssid"
  head "https://github.com/braineo/airport-bssid.git"

  depends_on :xcode => ["11.4", :build]
  depends_on :macos => :catalina

  def install
    system "swift", "build", "-c", "release", "--static-swift-stdlib", "--disable-sandbox"
    bin.install ".build/release/bssid"
  end

  test do
    system "#{bin}/bssid", "scan"
  end

  caveats <<~EOS
    BSSID requires your Developer Signing Identity, which can be found by issuing the following command on the CLI:
      security find-identity -v -p codesigning
    in order to provide entitlements to the binary (hard requirement for Catalina).
    The Identity may be set as an environment variable as follows:

      HOMEBREW_NO_ENV_FILTERING=1 SIGN_ID="abcdef123456" brew install bssid
  EOS
end
