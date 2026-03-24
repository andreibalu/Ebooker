//
//  CoverCropView.swift
//  Pageless
//

import SwiftUI

struct CoverCropView: View {
    let uiImage: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    // The square crop window displayed on screen
    private let cropSize: CGFloat = 300
    private let cropCornerRadius: CGFloat = 24

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var aspect: CGFloat { uiImage.size.width / uiImage.size.height }

    /// Size the image occupies at scale = 1 inside the crop square (scaledToFill equivalent).
    private var baseDisplaySize: CGSize {
        aspect >= 1
            ? CGSize(width: cropSize * aspect, height: cropSize)
            : CGSize(width: cropSize, height: cropSize / aspect)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    cropPreview

                    Text("Pinch to zoom  ·  Drag to reposition")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer()
                }
            }
            .navigationTitle("Crop Cover")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") {
                        onConfirm(renderCropped())
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Crop Preview

    private var cropPreview: some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: cropSize, height: cropSize)
            .clipShape(RoundedRectangle(cornerRadius: cropCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cropCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 2)
            )
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1.0, lastScale * value)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            clampAndSnapOffset()
                        },
                    DragGesture()
                        .onChanged { value in
                            offset = clamped(
                                CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
            )
    }

    // MARK: - Offset Clamping

    /// Clamps offset so the image always covers the entire crop square (no gaps).
    private func clamped(_ proposed: CGSize) -> CGSize {
        let scaledW = baseDisplaySize.width * scale
        let scaledH = baseDisplaySize.height * scale
        let maxX = max(0, (scaledW - cropSize) / 2)
        let maxY = max(0, (scaledH - cropSize) / 2)
        return CGSize(
            width: max(-maxX, min(maxX, proposed.width)),
            height: max(-maxY, min(maxY, proposed.height))
        )
    }

    private func clampAndSnapOffset() {
        offset = clamped(offset)
        lastOffset = offset
    }

    // MARK: - Render

    private func renderCropped() -> UIImage {
        let src = normalizedImage(uiImage)
        let W = src.size.width
        let H = src.size.height

        let scaledDispW = baseDisplaySize.width * scale
        let scaledDispH = baseDisplaySize.height * scale

        // Map the crop window origin back into image pixel coordinates.
        let pixelX = ((scaledDispW - cropSize) / 2 - offset.width) * (W / scaledDispW)
        let pixelY = ((scaledDispH - cropSize) / 2 - offset.height) * (H / scaledDispH)
        let pixelW = cropSize * (W / scaledDispW)
        let pixelH = cropSize * (H / scaledDispH)

        let cropRect = CGRect(x: pixelX, y: pixelY, width: pixelW, height: pixelH)
            .intersection(CGRect(origin: .zero, size: CGSize(width: W, height: H)))

        let outputSide: CGFloat = 600
        let outputRect = CGRect(origin: .zero, size: CGSize(width: outputSide, height: outputSide))

        let renderer = UIGraphicsImageRenderer(size: outputRect.size)
        return renderer.image { _ in
            if let cgCrop = src.cgImage?.cropping(to: cropRect) {
                UIImage(cgImage: cgCrop).draw(in: outputRect)
            } else {
                src.draw(in: outputRect)
            }
        }
    }

    /// Redraws the image into an upright orientation so CGImage.cropping works correctly.
    private func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: fmt).image { _ in
            image.draw(at: .zero)
        }
    }
}
