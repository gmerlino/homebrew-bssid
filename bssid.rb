require "English"
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

    # Identity discovery is optional: skip silently if it fails.
    identities = begin
      output = IO.popen(
        ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
        err: File::NULL,
        &:read
      )

      if $CHILD_STATUS.success?
        output.scan(/^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"/).flatten.uniq
      else
        []
      end
    rescue SystemCallError
      []
    end

    # Never guess which certificate to use.
    return unless identities.one?

    ohai "Signing bssid with identity #{identities.first}"

    begin
      system "/usr/bin/codesign",
             "--force",
             "--sign", identities.first,
             "--entitlements", buildpath/"bssid.entitlements",
             "--timestamp=none",
             bin/"bssid"
    rescue ErrorDuringExecution
      opoo "Optional code signing failed; bssid has still been installed."
    end
  end

  def caveats
    <<~EOS
      Upstream documents limitations when retrieving BSSIDs on macOS 10.15
      and later. Code signing is not a confirmed workaround.

      To connect using an SSID and channel instead:
        bssid connect --ssid <ssid> --channel <channel>

      See the upstream README for details:
        https://github.com/braineo/airport-bssid
    EOS
  end

  test do
    output = shell_output("#{bin}/bssid --help")
    assert_match "scan", output
    assert_match "connect", output
  end
end
