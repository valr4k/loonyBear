import Combine
import SwiftUI
import XCTest

@testable import LoonyBear

@MainActor
final class AppSystemDialogsTests: XCTestCase {
    func testArchiveAlertsUseNativeColorsForEveryTintAndTheme() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for tint in AppTint.allCases {
                try await checkPresentation(.archive, tint: tint, style: style)
            }
        }
    }

    func testRestoreChoicesUseNativeColorsForEveryTintAndTheme() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for tint in AppTint.allCases {
                try await checkPresentation(.restore, tint: tint, style: style)
            }
        }
    }

    func testDeleteAndDiscardKeepDestructiveRolesAndNativeCancel() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            try await checkPresentation(.delete, tint: .indigo, style: style)
            try await checkPresentation(.discard, tint: .amber, style: style)
        }
    }

    func testOpenAlertAdaptsWhenThemeChanges() async throws {
        try await checkPresentation(.archive, tint: .amber, style: .light, changesTheme: true)
    }

    func testPresentingContentRetainsItsTint() throws {
        for scheme in [ColorScheme.light, .dark] {
            for tint in AppTint.allCases {
                let original = sample
                    .appTintScope(tint)
                    .environment(\.colorScheme, scheme)
                let alert = sample
                    .appAlert("Test", isPresented: .constant(false)) {
                        Button("OK") {}
                    } message: { Text("Test") }
                    .appTintScope(tint)
                    .environment(\.colorScheme, scheme)
                let confirmation = sample
                    .appConfirmationDialog("Test", isPresented: .constant(false)) {
                        Button("OK") {}
                    } message: { Text("Test") }
                    .appTintScope(tint)
                    .environment(\.colorScheme, scheme)
                let expected = try XCTUnwrap(ImageRenderer(content: original).uiImage?.pngData())
                XCTAssertEqual(ImageRenderer(content: alert).uiImage?.pngData(), expected)
                XCTAssertEqual(ImageRenderer(content: confirmation).uiImage?.pngData(), expected)
            }
        }
    }

    private var sample: some View {
        Rectangle().fill(.tint).frame(width: 16, height: 16)
    }

    private func checkPresentation(
        _ kind: DialogFixture.Kind,
        tint: AppTint,
        style: UIUserInterfaceStyle,
        changesTheme: Bool = false
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.keyWindow
        let state = DialogFixtureState()
        let host = UIHostingController(rootView: DialogFixture(state: state, kind: kind).appTintScope(tint))
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        try await Task.sleep(for: .milliseconds(150))
        state.isPresented = true
        let presented = try await waitForPresentation(host, titles: kind.actionTitles)
        try await Task.sleep(for: .milliseconds(400))
        assertNativeColors(in: presented.view, kind: kind)
        attach(window, name: "\(kind)-\(tint.rawValue)-\(style.rawValue)")

        if changesTheme {
            window.overrideUserInterfaceStyle = .dark
            try await Task.sleep(for: .milliseconds(200))
            assertNativeColors(in: presented.view, kind: kind)
        }

        // Let SwiftUI finish dismissing before tearing down the fixture window.
        state.isPresented = false
        try await Task.sleep(for: .milliseconds(400))
    }

    private func waitForPresentation(_ host: UIViewController, titles: [String]) async throws -> UIViewController {
        for _ in 0..<100 {
            if let presented = host.presentedViewController,
               titles.allSatisfy({ title in labels(in: presented.view).contains { $0.text == title } }) {
                return presented
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("System dialog did not present its actions")
        throw NSError(domain: "AppSystemDialogsTests", code: 1)
    }

    private func assertNativeColors(in view: UIView, kind: DialogFixture.Kind) {
        for title in kind.actionTitles {
            let label = labels(in: view).first { $0.text == title }
            XCTAssertNotNil(label, "Missing \(title)")
            guard let label else { continue }
            if title == kind.destructiveTitle {
                // iOS 26 applies destructive red during rendering, not in UILabel.textColor.
                XCTAssertTrue(containsRenderedRed(in: view), "Missing destructive red for \(title)")
                continue
            }
            let attributedColor = label.attributedText.flatMap { text -> UIColor? in
                guard text.length > 0 else { return nil }
                return text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
            }
            XCTAssertEqual(
                (attributedColor ?? label.textColor).resolvedColor(with: label.traitCollection),
                UIColor.label.resolvedColor(with: label.traitCollection),
                "Wrong system color for \(title)"
            )
        }
    }

    private func containsRenderedRed(in view: UIView) -> Bool {
        let surface: UIView = view.window ?? view
        let image = UIGraphicsImageRenderer(bounds: surface.bounds).image { _ in
            surface.drawHierarchy(in: surface.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage else { return false }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return false }
        return stride(from: 0, to: pixels.count, by: 4).filter { index in
            let red = Int(pixels[index])
            return red > 160 && Int(pixels[index + 1]) * 2 < red && Int(pixels[index + 2]) * 2 < red
        }.count > 10
    }

    private func labels(in view: UIView) -> [UILabel] {
        (view as? UILabel).map { [$0] } ?? view.subviews.flatMap { labels(in: $0) }
    }

    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class DialogFixtureState: ObservableObject {
    @Published var isPresented = false

    var presentation: Binding<Bool> {
        Binding(
            get: { self.isPresented },
            set: { if self.isPresented != $0 { self.isPresented = $0 } }
        )
    }
}

private struct DialogFixture: View {
    enum Kind {
        case archive, delete, restore, discard

        var actionTitles: [String] {
            switch self {
            case .archive: ["Archive", "Cancel"]
            case .delete: ["Delete", "Cancel"]
            case .restore: ["Continue Progress", "Start From Scratch"]
            case .discard: ["Discard Changes"]
            }
        }

        var destructiveTitle: String? {
            switch self {
            case .delete: "Delete"
            case .discard: "Discard Changes"
            default: nil
            }
        }
    }

    @ObservedObject var state: DialogFixtureState
    let kind: Kind

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Text("Pill Details").appAccentForeground()
                if kind == .archive || kind == .delete {
                    Button("Present") { state.isPresented = true }
                        .appAlert(kind == .archive ? "Archive this Pill?" : "Delete this Pill?", isPresented: state.presentation) {
                            if kind == .archive {
                                Button("Archive") {}
                            } else {
                                Button("Delete", role: .destructive) {}
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: { Text("A confirmation message.") }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if kind == .restore || kind == .discard {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { state.isPresented = true } label: {
                            AppToolbarIconLabel("Save", systemName: "checkmark")
                        }
                        .appToolbarActionTint(isDisabled: false)
                        .appConfirmationDialog(
                            kind == .restore ? "Restore Pill?" : "Discard Changes?",
                            isPresented: state.presentation,
                            titleVisibility: .visible
                        ) {
                            if kind == .restore {
                                Button("Continue Progress") {}
                                Button("Start From Scratch") {}
                            } else {
                                Button("Discard Changes", role: .destructive) {}
                            }
                        } message: { Text("You can continue with your previous progress or start from scratch.") }
                    }
                }
            }
        }
    }
}
