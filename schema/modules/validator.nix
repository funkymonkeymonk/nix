{lib}: let
  profileModule = import ./profile.nix;
in rec {
  mkProfile = profileAttrs: let
    evaluated = lib.evalModules {
      modules = [
        profileModule
        {myProfile = profileAttrs;}
      ];
    };
  in
    if evaluated.options ? myProfile
    then evaluated.config.myProfile
    else
      throw ''
        mkProfile validation failed.

        The profile attrset must conform to the myProfile schema.
        Required fields: user.name, user.email, user.fullName.
        All other fields are optional with defaults.

        Errors:
        ${lib.concatMapStrings (e: "  - ${e}\n") (builtins.attrValues evaluated.errors)}
      '';
}
