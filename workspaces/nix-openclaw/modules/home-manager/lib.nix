# Shared helper functions for home-manager modules
{lib}:
with lib; rec {
  # Convert kebab-case to camelCase
  # Example: "my-api-key" -> "myApiKey"
  toCamelCase = str:
    lib.concatStrings (
      lib.imap0 (
        i: s:
          if i == 0
          then s
          else lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s
      ) (lib.splitString "-" str)
    );

  # Build opnix secrets configuration from a prefix and items
  # prefix: string prefix for secret names (e.g., "opencode", "claudeCode")
  # items: attrset of name -> { onePasswordItem, secretPath }
  mkOpnixSecrets = prefix: items:
    lib.mapAttrs' (name: item:
      lib.nameValuePair "${prefix}${toCamelCase name}ApiKey" {
        reference = item.onePasswordItem;
        path = item.secretPath;
        mode = "0600";
      })
    (lib.filterAttrs (_: item: item.onePasswordItem != "") items);
}
