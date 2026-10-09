import SwiftUI

extension View {
    func appAlert<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) -> some View {
        // Keep the screen's accent, but let iOS style the dialog and its action roles.
        appAccentTint()
            .alert(title, isPresented: isPresented, actions: actions, message: message)
            .tint(nil)
    }

    func appConfirmationDialog<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) -> some View {
        appAccentTint()
            .confirmationDialog(
                title,
                isPresented: isPresented,
                titleVisibility: titleVisibility,
                actions: actions,
                message: message
            )
            .tint(nil)
    }
}
