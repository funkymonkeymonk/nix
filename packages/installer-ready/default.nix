{
  writeShellApplication,
  coreutils,
  iproute2,
  openssh,
  systemd,
  util-linux,
}:
writeShellApplication {
  name = "installer-ready";
  runtimeInputs = [coreutils iproute2 openssh systemd util-linux];
  text = builtins.readFile ./installer-ready.sh;
}
