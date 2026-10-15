import PodcastCore
import SwiftUI

/// Android-style seek bar (AudioPlayerFragment / ChapterSeekBar): thin track, small round thumb,
/// chapter dividers on the same coordinates as the thumb. Accessibility is set by the caller.
struct SeekBar: View {
    let fraction: Double
    let chapterFractions: [Double]
    let onScrub: (Double) -> Void
    let onEnd: (Double) -> Void

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let w = Double(geo.size.width)
            let midY = geo.size.height / 2
            let thumbX = SeekBarGeometry.x(forFraction: fraction, width: w)
            let track = CGFloat(SeekBarGeometry.trackLength(width: w))
            let left = CGFloat(SeekBarGeometry.thumbDiameter / 2)
            let d = CGFloat(SeekBarGeometry.thumbDiameter)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: track, height: CGFloat(SeekBarGeometry.trackHeight))
                    .position(x: left + track / 2, y: midY)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, CGFloat(thumbX) - left), height: CGFloat(SeekBarGeometry.trackHeight))
                    .position(x: left + max(0, CGFloat(thumbX) - left) / 2, y: midY)
                ForEach(chapterFractions, id: \.self) { f in
                    Rectangle()
                        .fill(Color(uiColor: .systemBackground))
                        .frame(width: 2, height: CGFloat(SeekBarGeometry.trackHeight) + 2)
                        .position(x: CGFloat(SeekBarGeometry.x(forFraction: f, width: w)), y: midY)
                }
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: dragging ? d * 1.3 : d, height: dragging ? d * 1.3 : d)
                    .position(x: CGFloat(thumbX), y: midY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        onScrub(SeekBarGeometry.fraction(forX: Double(value.location.x), width: w))
                    }
                    .onEnded { value in
                        dragging = false
                        onEnd(SeekBarGeometry.fraction(forX: Double(value.location.x), width: w))
                    }
            )
        }
        .frame(height: CGFloat(SeekBarGeometry.hitHeight))
        .accessibilityElement()
    }
}
