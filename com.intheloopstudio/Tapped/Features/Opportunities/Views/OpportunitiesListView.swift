import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `opportunities_results_view.dart`: tiles with applied state; "select" enables batch apply.
struct OpportunitiesListView: View {
    @State private var model: OpportunitiesListViewModel
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, currentUser: UserModel, opportunities: [Opportunity]) {
        _model = State(initialValue: OpportunitiesListViewModel(dependencies: dependencies, currentUser: currentUser, opportunities: opportunities))
    }

    var body: some View {
        screen
    }

    @ViewBuilder private var screen: some View {
        List {
            Section {
                ForEach(model.opportunities) { opportunity in
                    row(opportunity)
                }
            } header: {
                if model.isSelecting { Text("select gigs to apply in one go") }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.opportunities.isEmpty {
                GlassEmptyState("no gigs here", message: "try another area on the map", systemImage: "music.mic")
            }
        }
        .navigationTitle("opportunities")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.selectable.isEmpty {
                if model.isSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(model.allSelected ? "deselect all" : "select all") {
                            withAnimation(GlassMotion.spring) { model.selectAll(!model.allSelected) }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isSelecting ? "done" : "select") {
                        withAnimation(GlassMotion.spring) { model.isSelecting.toggle() }
                    }
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            if model.isSelecting && !model.selectedIds.isEmpty {
                Button {
                    Task {
                        _ = await model.applySelected()
                    }
                } label: {
                    HStack(spacing: TappedSpacing.sm) {
                        if model.isApplying { ProgressView() }
                        Text(Self.applyTitle(count: model.selectedIds.count))
                    }
                    .font(TappedTypography.headingXs)
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .disabled(model.isApplying)
                .tappedFloatingInset()
                .padding(.bottom, TappedSpacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Couldn't Apply", isPresented: Binding { model.errorMessage != nil } set: { if !$0 { model.dismissError() } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.load() }
    }

    static func applyTitle(count: Int) -> String {
        return "apply to \(count) \(count == 1 ? "gig" : "gigs")"
    }

    private func row(_ opportunity: Opportunity) -> some View {
        let isApplied = model.appliedIds.contains(opportunity.id)
        return Button {
            if model.isSelecting {
                withAnimation(GlassMotion.spring) { model.toggle(opportunity) }
            } else {
                router.push(.opportunity(opportunityId: opportunity.id, opportunity: opportunity))
            }
        } label: {
            HStack(spacing: TappedSpacing.md) {
                if model.isSelecting {
                    SelectionIndicator(isSelected: model.selectedIds.contains(opportunity.id))
                        .opacity(isApplied ? 0.3 : 1)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                OpportunityTile(opportunity: opportunity, venueName: model.venueName(for: opportunity)) {
                    if isApplied {
                        SwiftUI.Label("applied", systemImage: "checkmark.circle.fill")
                            .font(TappedTypography.label)
                            .foregroundStyle(TappedColors.accent)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        OpportunitiesListView(dependencies: .mock(signedIn: true), currentUser: Samples.performer, opportunities: Samples.opportunities)
    }
    .environment(Router())
}
