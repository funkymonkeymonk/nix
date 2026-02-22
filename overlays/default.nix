# Custom package overlays
final: prev: {
  rtk = final.callPackage ../packages/rtk {};
}
