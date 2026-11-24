{pkgs}:
pkgs.runCommand "test-devenv-grafana-skills" {
  nativeBuildInputs = [pkgs.gnugrep];
} ''
  grep -q '^  grafana-skills:' ${../devenv.yaml}
  grep -q 'grafana-core' ${../devenv.nix}
  grep -q 'grafana-lgtm/loki' ${../devenv.nix}
  grep -q 'grafana-lgtm/prometheus' ${../devenv.nix}
  grep -q 'grafana-datasources/datasources-provisioning' ${../devenv.nix}
  grep -q '\.agents/skills' ${../devenv.nix}
  ! grep -q 'grafana-cloud' ${../devenv.nix}
  ! grep -q 'grafana-plugins' ${../devenv.nix}
  ! grep -q 'grafana-app-sdk' ${../devenv.nix}
  ! grep -q 'grafana-k6' ${../devenv.nix}
  touch $out
''
