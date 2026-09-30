import SwiftUI
import TappedDomain
import TappedUI

/// Apply confirmation: optional note for the booker, remaining quota, then "application sent".
struct ApplySheet: View {
    let opportunity: Opportunity
    let remainingQuota: Int?
    let apply: (String) async -> OpportunityApplication.Outcome?
    let onNeedsPremium: () -> Void

    @State private var comment = ""
    @State private var isSending = false
    @State private var isSent = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isSent {
                    ContentUnavailableView {
                        SwiftUI.Label("application sent", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(TappedColors.success)
                    } description: {
                        Text("we just received your application, thanks for applying")
                    } actions: {
                        Button("Done") { dismiss() }
                            .buttonStyle(.glassProminent)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    form
                }
            }
            .navigationTitle("apply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: isSent)
    }

    private var form: some View {
        Form {
            Section {
                OpportunityTile(opportunity: opportunity)
            }
            Section {
                TextField("add a note for the booker (optional)", text: $comment, axis: .vertical)
                    .lineLimit(3...6)
            } footer: {
                Text(ApplicationQuota.caption(remaining: remainingQuota).map { "\($0). premium makes it unlimited." } ?? ApplicationQuota.premiumCaption)
            }
            Section {
                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        Spacer()
                        if isSending {
                            ProgressView()
                        } else if remainingQuota == 0 {
                            SwiftUI.Label(ApplicationQuota.applyWithPremium, systemImage: "sparkles").fontWeight(.semibold)
                        } else {
                            Text("send application").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(isSending)
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        switch await apply(comment) {
        case .applied:
            withAnimation(GlassMotion.spring) { isSent = true }
        case .needsPremium:
            dismiss()
            onNeedsPremium()
        case nil:
            break
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ApplySheet(opportunity: Samples.opportunities[0], remainingQuota: 2, apply: { _ in .applied }, onNeedsPremium: {})
            .presentationDetents([.medium, .large])
    }
}
