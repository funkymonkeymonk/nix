{
  kind,
  extraSpecialArgs ? {},
  overrides ? {},
}: machine:
{
  inherit kind extraSpecialArgs overrides;
  builder = "mk-system";
}
// machine
