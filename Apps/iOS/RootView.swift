import HabitUI
import SwiftUI

/// M0 placeholder: app name and build number. Replaced by the Today screen in M2.
struct RootView: View {
    private let buildInfo = BuildInfo(infoDictionary: Bundle.main.infoDictionary)

    var body: some View {
        VStack(spacing: 16) {
            Image("LogoMark")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Spaced Habits")
                .font(.largeTitle.bold())
                .foregroundStyle(Color("BrandInk"))
            Text(buildInfo.displayString)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("BrandPaper"))
    }
}

#Preview {
    RootView()
}
