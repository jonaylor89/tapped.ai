import SwiftUI
import TappedUI

/// Landing screen (`splash_view.dart`). While `AppSession` resolves auth, the actions are hidden and a
/// spinner is shown instead.
struct SplashView: View {
    var isLoading: Bool = true
    var getStarted: () -> Void = {}
    var logIn: () -> Void = {}

    var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Image("TappedLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 36)
                    .colorScheme(.dark)
                    .accessibilityLabel("tapped")
                Spacer()
                Text("get booked.\nget paid.")
                    .font(.system(size: 52, weight: .heavy))
                    .kerning(-1.5)
                    .lineSpacing(-4)
                    .foregroundStyle(.white)
                Text("the booking network for performers and venues")
                    .font(TappedTypography.bodyLg)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, TappedSpacing.sm)
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, minHeight: GlassMetrics.control * 2 + TappedSpacing.md)
                    } else {
                        VStack(spacing: TappedSpacing.md) {
                            Button(action: getStarted) {
                                Text("get started").frame(maxWidth: .infinity, minHeight: GlassMetrics.control)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(TappedColors.accent)
                            Button(action: logIn) {
                                Text("log in").frame(maxWidth: .infinity, minHeight: GlassMetrics.control)
                            }
                            .buttonStyle(.glass)
                            .foregroundStyle(.white)
                        }
                        .font(.body.weight(.semibold))
                    }
                }
                .padding(.top, TappedSpacing.xxl)
            }
            .padding(.horizontal, GlassMetrics.edgeInset + TappedSpacing.xs)
            .padding(.bottom, TappedSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                Color.black
                    .overlay {
                        Image("SplashBackground")
                            .resizable()
                            .scaledToFill()
                    }
                    .overlay {
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.75), location: 1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .clipped()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
    }
}

#Preview("loading") { SplashView() }
#Preview("signed out") { SplashView(isLoading: false) }
