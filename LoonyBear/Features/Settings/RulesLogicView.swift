import SwiftUI

struct RulesLogicView: View {
    @State private var loadState: RulesLogicLoadState = .loading

    var body: some View {
        AppScreen(backgroundStyle: .settings) {
            switch loadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 240)
            case .loaded(let content):
                ForEach(content.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        AppCard {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                ruleItemView(item)

                                if index < section.items.count - 1 {
                                    AppSectionDivider()
                                }
                            }
                        }
                    }
                }
            case .unavailable:
                ContentUnavailableView(
                    "Rules & Logic unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("This reference content could not be loaded right now.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard case .loading = loadState else { return }
            if let content = RulesLogicContentLoader.load() {
                loadState = .loaded(content)
            } else {
                loadState = .unavailable
            }
        }
    }

    private var navigationTitle: String {
        if case .loaded(let content) = loadState {
            return content.title
        }
        return "Rules & Logic"
    }

    private func ruleItemView(_ item: RulesLogicItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(item.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

private enum RulesLogicLoadState {
    case loading
    case loaded(RulesLogicContent)
    case unavailable
}

struct RulesLogicContent: Decodable {
    let title: String
    let sections: [RulesLogicSection]
}

struct RulesLogicSection: Decodable, Identifiable {
    let title: String
    let items: [RulesLogicItem]

    var id: String { title }
}

struct RulesLogicItem: Decodable, Identifiable {
    let title: String
    let body: String

    var id: String { title }
}

enum RulesLogicContentLoader {
    static func load(bundle: Bundle = .main) -> RulesLogicContent? {
        let decoder = JSONDecoder()
        let candidateURLs = [
            bundle.url(forResource: "RulesLogicContent", withExtension: "json", subdirectory: "Resources"),
            bundle.url(forResource: "RulesLogicContent", withExtension: "json"),
        ]

        for url in candidateURLs.compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let content = try? decoder.decode(RulesLogicContent.self, from: data) {
                return content
            }
        }

        return nil
    }
}

#Preview {
    NavigationStack {
        RulesLogicView()
    }
}
