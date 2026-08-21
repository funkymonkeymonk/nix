# Work role — marks a machine as used in an employer/work context.
#
# This is intentionally a no-op role with no packages or system config of
# its own. It exists purely as a signal (myConfig.roles.work.enable) that
# other modules/skills can key off of — e.g. tagging work-specific agent
# skills (innersource-pr-haiku) or, in the future, defaulting the 1Password
# vault. Orthogonal to workstation (machine form-factor): a personal desktop
# and a work laptop can both be "workstation" archetypes, but only the work
# laptop enables this role.
{...}: {}
