import SwiftUI

/// Plain controls respond throughout their laid-out label, including spacers
/// and padding. Keep the box inside the button so empty selected-row space
/// has the same hit area before and after selection.
struct MacBoxButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack { configuration.label }
            .contentShape(Rectangle())
    }
}
