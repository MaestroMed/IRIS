import SwiftUI

// IRIS v0.0.1 — ContentView minimal "Hello Mehdi".
// v0.0.2 ajoutera le NavigationSplitView 3 panels (sidebar agents / main / inspector).

struct ContentView: View {
    var body: some View {
        ZStack {
            // Background Liquid Glass — gradient soft iris → sky cohérent MIND
            LinearGradient(
                colors: [IRISTokens.skyBackground, IRISTokens.aquaTint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Text("IRIS")
                    .font(.system(size: 96, weight: .ultraLight, design: .serif))
                    .foregroundStyle(IRISTokens.irisAccent)
                    .tracking(8)

                Text("Hello Mehdi")
                    .font(.system(size: 24, weight: .regular, design: .default))
                    .foregroundStyle(.primary.opacity(0.7))

                Text("v0.0.1 — bootstrap")
                    .font(.system(size: 12, weight: .light, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Exocortex local desktop multi-agents.\nPendant desktop de MIND.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)
            }
            .padding(48)
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1400, height: 900)
}
