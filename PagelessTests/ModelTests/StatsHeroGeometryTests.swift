import CoreGraphics
import Testing
@testable import Pageless

/// Isolated on purpose: no E2E device is narrower than 375 pt, and AGENTS.md requires the stats
/// chrome to stay usable at Display Zoom's 320 pt width (280 pt inside the hero's padding).
@MainActor
struct StatsHeroGeometryTests {
    /// Interactive slots are `cell + gap` wide; the four-month grid adds a 30 pt weekday label column.
    private func width(_ scale: HeatmapScale, _ g: (cell: CGFloat, gap: CGFloat, radius: CGFloat)) -> CGFloat {
        switch scale {
        case .week:      return 7 * (g.cell + g.gap)
        case .month:     return 30 * (g.cell + g.gap)
        case .fourMonth: return 30 + 18 * (g.cell + g.gap)
        }
    }

    @Test(arguments: [HeatmapScale.week, .month, .fourMonth], [280.0, 335.0, 390.0, 600.0])
    func fittedHeatmapNeverExceedsTheColumn(scale: HeatmapScale, available: Double) {
        let g = StatsHeroSection.fittedGeometry(scale: scale, availableWidth: CGFloat(available))
        #expect(width(scale, g) <= CGFloat(available) + 0.001)
    }

    @Test func wideColumnKeepsThePreferredSize() {
        let g = StatsHeroSection.fittedGeometry(scale: .fourMonth, availableWidth: 600)
        #expect(g.cell == 14 && g.gap == 4)
    }

    @Test func unmeasuredWidthKeepsThePreferredSize() {
        let g = StatsHeroSection.fittedGeometry(scale: .week, availableWidth: 0)
        #expect(g.cell == 40 && g.gap == 10)
    }
}
