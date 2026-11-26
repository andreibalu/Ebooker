import SwiftUI
import Testing
import UIKit
@testable import Pageless

/// Isolated on purpose: the hero grid overflows the 320 pt Display Zoom width, which no simulator
/// device can show, so E2E can't catch it.
@MainActor
struct StatsHeroGeometryTests {
    @Test(arguments: [HeatmapScale.week, .month, .fourMonth])
    func fittedHeroHeatmapFitsWithinDisplayZoomColumn(scale: HeatmapScale) {
        let availableWidth: CGFloat = 280
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26))!
        let firstDay = calendar.date(byAdding: .day, value: -120, to: today)!

        let model = HeatmapGridModel.build(
            scale: scale,
            today: today,
            firstDay: firstDay,
            activityByDay: [:],
            calendar: calendar
        )
        let geometry = StatsHeroSection.fittedGeometry(scale: scale, availableWidth: availableWidth)
        let view = ReadingHeatmapView(
            model: model,
            palette: .amber,
            cellSize: geometry.cell,
            gap: geometry.gap,
            radius: geometry.radius,
            showLabels: true,
            stagger: false
        )

        let host = UIHostingController(rootView: view)
        let fitted = host.sizeThatFits(in: CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
        #expect(fitted.width <= availableWidth + 0.001)
    }
}
