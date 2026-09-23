{
  description = "Import k1m0ch1's Claude Code / CCS / cliproxy config (nix run github:k1m0ch1/harness-config)";

  outputs = { self }: {
    apps.x86_64-linux.default = {
      type = "app";
      program = "${self}/install.sh";
    };
    apps.aarch64-linux.default = self.apps.x86_64-linux.default;
    apps.x86_64-darwin.default = self.apps.x86_64-linux.default;
    apps.aarch64-darwin.default = self.apps.x86_64-linux.default;
  };
}
