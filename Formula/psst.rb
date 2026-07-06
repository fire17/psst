# Homebrew formula for psst — tap-ready.
# brew install fire17/tap/psst  (formula also lives in fire17/homebrew-tap)
class Psst < Formula
  desc "Gentle hints for your shell, right before you need them"
  homepage "https://github.com/fire17/psst"
  url "https://github.com/fire17/psst/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "14c709d81c4dd98ff941922114262c944ce9eb125cad0046652d4e9743bc72d2"
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
