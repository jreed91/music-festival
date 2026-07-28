import SwiftUI
import UIKit

/// Routes into the map screens, pushed from the Maps tab's own navigation stack.
enum MapRoute: Hashable {
    /// The georeferenced grounds map on MapKit, with the blue dot.
    case grounds
    /// A bundled map image, by `FestivalMap.id`.
    case image(String)
}

/// A map row's thumbnail — bundled artwork, so it draws with no network.
struct MapThumbnail: View {
    let asset: String

    var body: some View {
        Group {
            if UIImage(named: asset) != nil {
                Image(asset).resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.surfaceRaised
                    Image(systemName: "map")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Full-screen map image

/// A bundled map, pinch-zoomable. `UIScrollView` rather than SwiftUI gestures so that
/// double-tap-to-zoom, momentum and the zoom bounds behave the way they do everywhere
/// else on the phone.
struct MapImageView: View {
    let map: FestivalMap

    var body: some View {
        ZoomableImage(imageName: map.asset)
            .background(Theme.background)
            .navigationTitle(map.title)
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea(edges: .bottom)
    }
}

struct ZoomableImage: UIViewRepresentable {
    let imageName: String

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = ZoomingScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 8
        scrollView.minimumZoomScale = 1
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        scrollView.imageView = imageView
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// SwiftUI hands `makeUIView` a zero-size view, so the image is sized in layout
    /// rather than up front — and left alone once the user has zoomed in.
    final class ZoomingScrollView: UIScrollView {
        var imageView: UIImageView?

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let imageView, zoomScale == minimumZoomScale else { return }
            imageView.frame = bounds
            contentSize = bounds.size
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        /// Keep the artwork centred while it is smaller than the screen.
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let extraWidth = max(0, scrollView.bounds.width - imageView.frame.width) / 2
            let extraHeight = max(0, scrollView.bounds.height - imageView.frame.height) / 2
            scrollView.contentInset = UIEdgeInsets(top: extraHeight, left: extraWidth,
                                                   bottom: extraHeight, right: extraWidth)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let side = scrollView.bounds.size.width / 3
                scrollView.zoom(to: CGRect(x: point.x - side / 2, y: point.y - side / 2,
                                           width: side, height: side), animated: true)
            }
        }
    }
}
