# Work role — marks a machine as used in an employer/work context.
#
# This is intentionally a no-op role with no packages or system config of
# its own. It exists purely as a signal (myConfig.roles.work.enable) that
# other modules/skills can key off of — e.g. tagging work-specific agent
# skills (innersource-pr-haiku) or, in the future, defaulting the 1Password
# vault. Orthogonal to workstation (machine form-factor): a personal desktop
# and a work laptop can both be "workstation" archetypes, but only the work
# laptop enables this role.
{lib, ...}: {
  options.myConfig.roles.work.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "This machine is used for an employer/work context (as opposed to purely personal use). Orthogonal to workstation (machine form-factor) — set explicitly per-host, not via a shared archetype.";
  };
}
