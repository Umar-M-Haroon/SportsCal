#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

/// A water ripple spreading from each place a pack or team just lit up, applied to the
/// onboarding map's dot layer. `origins` holds x,y pairs in the layer's points; every
/// ring starts together at `time` 0 and dies away within about a second and a half.
[[ stitchable ]] half4 leagueMapRipple(float2 position, SwiftUI::Layer layer,
                                       float time,
                                       device const float *origins, int count,
                                       float amplitude, float speed) {
    float2 offset = float2(0);
    float glow = 0;
    for (int i = 0; i + 1 < count; i += 2) {
        float2 origin = float2(origins[i], origins[i + 1]);
        float distanceFromOrigin = distance(position, origin);
        // How long ago the wave front passed this point.
        float delay = distanceFromOrigin / speed;
        float t = max(time - delay, 0.0);
        if (t <= 0.0) { continue; }
        float wave = sin(16.0 * t) * exp(-4.0 * t) * exp(-distanceFromOrigin / 260.0);
        float2 direction = distanceFromOrigin > 0.001 ? (position - origin) / distanceFromOrigin : float2(0);
        offset += direction * wave * amplitude;
        glow += max(wave, 0.0);
    }
    half4 color = layer.sample(position - offset);
    // Brighten the dots the crest passes over, a little.
    return half4(color.rgb * (1.0h + half(min(glow, 1.0)) * 1.6h), color.a);
}
