import SwiftUI

struct PersistenceErrorView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Failed to load app data")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                Text("LoonyBear couldn’t open its local database.")
                Text("You may need to reinstall the app or restore your data from backup.")
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
    }
}

#Preview {
    PersistenceErrorView(error: NSError(domain: "LoonyBear", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "The persistent store couldn’t be opened."
    ]))
}
