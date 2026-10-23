import SwiftUI

/// A frosted capsule whose edge melts into what is behind it: the material
/// and a faint white wash, masked by a blurred capsule so the frost fades
/// out over the last few points instead of stopping at a rim. Sits behind
/// the listening buttons over a result; the frost strips in `ResultView`
/// are the same recipe along one edge.
struct FrostedCapsule: View {
    /// How wide the fade at the edge is, in points.
    var edgeFade: CGFloat = 6

    var body: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(.white.opacity(0.55))
        }
        .mask {
            // Inset by the fade and blurred by it: the core stays opaque and
            // the alpha reaches zero at the frame's edge, all the way round.
            Capsule()
                .fill(.white)
                .padding(edgeFade)
                .blur(radius: edgeFade)
        }
        .allowsHitTesting(false)
    }
}
