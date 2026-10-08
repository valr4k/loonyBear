import Foundation
import Testing

@testable import LoonyBear

@MainActor
struct FutureStartLabelTests {
    @Test
    func defaultLabelKeepsDateOnOneLine() {
        let date = TestSupport.makeDate(2026, 10, 20)

        #expect(FutureStartLabel.text(for: date) == "Starts 20 Oct 2026")
    }

    @Test
    func stackedLabelMovesCompleteDateToSecondLine() {
        let date = TestSupport.makeDate(2026, 10, 20)

        #expect(FutureStartLabel.text(for: date, stacked: true) == "Starts\n20 Oct 2026")
    }
}
