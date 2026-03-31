# Custom package overlays
final: _prev: {
  rtk = final.callPackage ../packages/rtk {};
  yaks = final.callPackage ../packages/yaks {};
  pi-coding-agent = final.callPackage ../packages/pi-coding-agent {};
}
