import Testing

@testable import LoonyBear

@Suite
struct AppBuildVersionFormatterTests {
    @Test
    func displayBuildPadsNumericBuildsToSixDigits() {
        #expect(AppBuildVersionFormatter.displayBuild("1025") == "001025")
        #expect(AppBuildVersionFormatter.displayBuild("42") == "000042")
    }

    @Test
    func displayBuildKeepsNonNumericBuildsUnchanged() {
        #expect(AppBuildVersionFormatter.displayBuild("—") == "—")
    }
}
