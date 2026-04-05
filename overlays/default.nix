# Custom package overlays
final: _prev: {
  rtk = final.callPackage ../packages/rtk {};
  yaks = final.callPackage ../packages/yaks {};
  pi-coding-agent = final.callPackage ../packages/pi-coding-agent {};

  # Pin opencode to 1.2.15 to avoid edit hanging bug in 1.3.10
  # https://github.com/anomalyco/opencode/issues/20477
  opencode = _prev.opencode.overrideAttrs (oldAttrs: rec {
    version = "1.2.15";
    src = _prev.fetchFromGitHub {
      owner = "anomalyco";
      repo = "opencode";
      tag = "v${version}";
      hash = "sha256-26MV9TbyAF0KFqZtIHPYu6wqJwf0pNPdW/D3gDQEUlQ=";
    };
    node_modules = oldAttrs.node_modules.overrideAttrs {
      outputHash = "sha256-Diu/C8b5eKUn7MRTFBcN5qgJZTp0szg0ECkgEaQZ87Y=";
    };
  });
}
