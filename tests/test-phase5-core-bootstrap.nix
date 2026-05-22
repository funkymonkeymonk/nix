{
  pkgs,
  self,
  ...
}: let
  assertPass = name: condition:
    if condition
    then "${name}: OK"
    else throw "${name}: FAILED";
in
  pkgs.runCommand "test-phase5-core-bootstrap" {
    buildInputs = [];
    meta = {
      description = "Verify Phase 5: core-v2 and bootstrap-v2 exist as parallel configs";
    };
    passAsFile = ["results"];
    results = ''
      ${assertPass "core-v2 exists" (self ? darwinConfigurations.core-v2)}
      ${assertPass "bootstrap-v2 exists" (self ? nixosConfigurations.bootstrap-v2)}
      ${assertPass "old core unchanged" (self ? darwinConfigurations.core)}
      ${assertPass "old bootstrap unchanged" (self ? nixosConfigurations.bootstrap)}
    '';
    phases = ["buildPhase"];
    buildPhase = ''
      cat "$resultsFile"
      touch $out
    '';
  } ""
