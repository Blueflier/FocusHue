import SwiftUI

struct OnboardingView: View {
    @Environment(PermissionManager.self) private var permissionManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        // this needs to have an onboarding for which permissions to grant
}

#Preview {
    OnboardingView()
        .environment(PermissionManager())
}
