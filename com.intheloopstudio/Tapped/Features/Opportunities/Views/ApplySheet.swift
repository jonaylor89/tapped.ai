import SwiftUI
import TappedDomain
import TappedUI

/// Apply confirmation: optional note for the booker, then "application sent".
struct ApplySheet: View {
    let opportunity: Opportunity
    let apply: (String) async -> OpportunityApplication.Outcome?

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
                        NotificationsPromptCard(context: .application, venueId: opportunity.venueId ?? opportunity.userId)
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
            }
            Section {
                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        Spacer()
                        if isSending {
                            ProgressView()
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
        case nil:
            break
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ApplySheet(opportunity: Samples.opportunities[0], apply: { _ in .applied })
            .presentationDetents([.medium, .large])
    }
}
