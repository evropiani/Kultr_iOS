import SwiftUI

/** Artwork URL for a cover id at a size bucket, or nil when signed out. */
@MainActor
func artworkUrl(_ coverId: String?, _ size: Int) -> URL? {
    // Snap to a few sizes so the same cover is not fetched at every pixel size.
    let bucket = size <= 96 ? 96 : size <= 200 ? 200 : size <= 400 ? 400 : 800
    return AppGraph.shared.auth.client?.coverArtUrl(coverId, size: bucket)
}

private func bucketFor(_ size: Int) -> Int {
    size <= 96 ? 96 : size <= 200 ? 200 : size <= 400 ? 400 : 800
}

/**
 * Cover art with a graceful placeholder: a gradient in the accent with the
 * initials of whatever it is, so an album without artwork still looks placed.
 */
struct Artwork: View {
    @Environment(\.kultr) private var theme
    let coverId: String?
    var size: CGFloat = 48
    var circle = false
    var label: String?
    var icon = "music.note"
    var imageUrl: URL?

    var body: some View {
        let url = imageUrl ?? artworkUrl(coverId, Int(size * 3))
        let shape = RoundedRectangle(cornerRadius: circle ? size / 2 : theme.radii.sm, style: .continuous)
        ZStack {
            LinearGradient(
                colors: [theme.colors.accent.opacity(0.55), theme.colors.accent.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let label {
                Text(Format.initials(label))
                    .font(.system(size: min(48, max(10, size * 0.3)), weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let url {
                RemoteImage(url: url, pixelSize: bucketFor(Int(size * 3)))
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }
}

/** Artwork that fills its parent's width (square), for cards and headers. */
struct ArtworkFill: View {
    @Environment(\.kultr) private var theme
    let coverId: String?
    var circle = false
    var radius: CGFloat?
    var label: String?
    var pixels = 400
    var imageUrl: URL?

    var body: some View {
        let url = imageUrl ?? artworkUrl(coverId, pixels)
        let shape = RoundedRectangle(cornerRadius: radius ?? theme.radii.md, style: .continuous)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    LinearGradient(
                        colors: [theme.colors.accent.opacity(0.55), theme.colors.accent.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    if let label {
                        Text(Format.initials(label))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if let url {
                        RemoteImage(url: url, pixelSize: bucketFor(pixels))
                    }
                }
            }
            .clipShape(circle ? AnyShape(Circle()) : AnyShape(shape))
    }
}
