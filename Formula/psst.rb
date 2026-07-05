# Homebrew formula for psst — tap-ready.
# brew install fire17/tap/psst  (formula also lives in fire17/homebrew-tap)
class Psst < Formula
  desc "Gentle hints for your shell, right before you need them"
  homepage "https://github.com/fire17/psst"
  url "https://github.com/fire17/psst/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "9c593ca0d4179ff1f91c4dc5855c5c5432736b87f062acffdc67a0cc669dfc1b"
  license "MIT"

  depends_on "zsh"

  def install
    prefix.install "psst.plugin.zsh", "lib", "packs"
    bin.install "bin/psst"
    # the CLI resolves its root as bin/.. — keep layout intact
  end

  def caveats
    <<~EOS
      To activate the hints hook, add to your ~/.zshrc:
        source #{opt_prefix}/psst.plugin.zsh
    EOS
  end

  test do
    ENV["PSST_DIR"] = testpath.to_s
    ENV["PSST_HINTS"] = "#{testpath}/hints.tsv"
    system "#{bin}/psst", "add", "nano", "try fresh!"
    assert_match "try fresh!", shell_output("#{bin}/psst list --porcelain")
  end
end
