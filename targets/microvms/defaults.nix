# Default configuration for all MicroVMs
# Provides shared user config, skills, and disables 1Password
# Individual VM configs can override these defaults via roleEnables specialArg
{
  inputs,
  roleEnables,
  lib,
  ...
}: {
  # Don't set hostPlatform here - it should come from the system parameter in mkMicrovm
  # This allows different architectures (x86_64-linux, aarch64-linux)
  myConfig = lib.mkMerge [
    {
      skills = {
        superpowersPath = inputs.superpowers;
        externalInputs = {
          inherit (inputs) vercel-skills;
        };
      };
      users = [
        {
          name = "dev";
          email = "dev@localhost";
          fullName = "Development User";
          isAdmin = true;
          sshIncludes = [];
        }
      ];
      onepassword.enable = lib.mkForce false;
      # MicroVMs are static once deployed - they are replaced rather than upgraded.
      # Leaving flakeUrl empty disables auto-upgrade in the auto-upgrade module.
      autoUpgrade.flakeUrl = lib.mkForce "";
    }
    roleEnables
  ];
}
