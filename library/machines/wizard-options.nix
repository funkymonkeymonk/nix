# Choices offered by the machine-target wizard. Archetypes are complete
# profiles; roles remain separate so a profile cannot be selected as a role.
{
  aarch64-darwin = {
    archetypes = [
      {
        label = "Developer workstation";
        kind = "darwin";
        module = "library/archetypes/workstation-darwin.nix";
      }
      {
        label = "Virtualization server";
        kind = "darwin";
        module = "library/archetypes/vm-management-darwin.nix";
      }
      {
        label = "Headless inference server";
        kind = "darwin";
        module = "library/archetypes/headless-inference-darwin.nix";
      }
    ];
    roles = [
      "developer"
      "creative"
      "gaming"
      "desktop"
      "workstation"
      "work"
      "entertainment"
      "homebrew"
      "agent-skills"
      "opencode"
      "claude"
      "pi"
      "assistant"
      "email-backup"
    ];
  };

  x86_64-linux = {
    archetypes = [
      {
        label = "Desktop";
        kind = "nixos";
        module = "library/archetypes/desktop-nixos.nix";
      }
      {
        label = "Headless server";
        kind = "nixos";
        module = "library/archetypes/headless-server-nixos.nix";
      }
      {
        label = "Type server";
        kind = "nixos";
        module = "library/archetypes/type-server.nix";
      }
    ];
    roles = [
      "developer"
      "creative"
      "gaming"
      "desktop"
      "workstation"
      "work"
      "entertainment"
      "agent-skills"
      "opencode"
      "claude"
      "pi"
      "assistant"
      "email-backup"
    ];
  };

  aarch64-linux = {
    archetypes = [
      {
        label = "Headless server";
        kind = "nixos";
        module = "library/archetypes/headless-server-nixos.nix";
      }
      {
        label = "Type server";
        kind = "nixos";
        module = "library/archetypes/type-server.nix";
      }
    ];
    roles = [
      "developer"
      "creative"
      "gaming"
      "desktop"
      "workstation"
      "work"
      "entertainment"
      "agent-skills"
      "opencode"
      "claude"
      "pi"
      "assistant"
      "email-backup"
    ];
  };
}
