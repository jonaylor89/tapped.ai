import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/tasks/tasks_view.dart` ("finish setting up").
struct TasksView: View {
    @Environment(Router.self) private var router
    @State private var model: TasksViewModel

    init(dependencies: Dependencies, currentUser: UserModel) {
        _model = State(initialValue: TasksViewModel(dependencies: dependencies, currentUser: currentUser))
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: TappedSpacing.lg) {
                    Gauge(value: model.progress) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(model.completedCount)/\(model.tasks.count)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(TappedColors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("finish setting up")
                            .font(.headline)
                        Text(model.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, TappedSpacing.xs)
                .accessibilityElement(children: .combine)
            }

            Section {
                ForEach(model.tasks) { task in
                    Button { router.push(task.route) } label: {
                        TaskRow(task: task)
                    }
                    .tint(.primary)
                    .disabled(task.isCompleted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("tasks")
        .navigationBarTitleDisplayMode(.inline)
        .redacted(reason: model.isLoading ? .placeholder : [])
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

struct TaskRow: View {
    let task: SetupTask

    var body: some View {
        HStack(spacing: TappedSpacing.md) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : task.systemImage)
                .font(.title2)
                .foregroundStyle(task.isCompleted ? TappedColors.success : TappedColors.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                Text(task.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !task.isCompleted {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, TappedSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityValue(task.isCompleted ? "completed" : "not completed")
    }
}

#Preview {
    NavigationStack {
        TasksView(dependencies: .mock(signedIn: true), currentUser: Samples.performer)
    }
    .environment(Router())
}
