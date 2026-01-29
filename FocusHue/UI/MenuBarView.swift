import SwiftUI

struct MenuBarView: View {
    @Binding var isEnabled: Bool

    var body: some View {
        VStack {
            Text("Menu Bar")
        }
}

#Preview {
    MenuBarView(isEnabled: .constant(true))
}
