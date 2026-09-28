import SwiftUI
import TappedDomain

public extension Service {
    /// `$150 / hr` or `$250 flat` (rate is stored in cents).
    var formattedRate: String {
        let dollars = (Double(rate) / 100).formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(rate % 100 == 0 ? 0 : 2)))
        return switch rateType {
        case .hourly: "\(dollars) / hr"
        case .fixed: "\(dollars) flat"
        }
    }
}

public extension RateType {
    var formattedName: String {
        switch self {
        case .hourly: "per hour"
        case .fixed: "flat fee"
        }
    }
}

/// A service in an inset-grouped list (`service_card.dart`).
public struct ServiceRow: View {
    let service: Service

    public init(service: Service) {
        self.service = service
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TappedSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.title)
                    .font(TappedTypography.headingXs)
                if !service.description.isEmpty {
                    Text(service.description)
                        .font(TappedTypography.bodySm)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Text(service.formattedRate)
                .font(TappedTypography.label)
                .monospacedDigit()
                .foregroundStyle(TappedColors.accent)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("ServiceRow") {
    List {
        ForEach(Samples.services) { ServiceRow(service: $0) }
    }
}

#Preview("ServiceRow dark") {
    List {
        ForEach(Samples.services) { ServiceRow(service: $0) }
    }
    .preferredColorScheme(.dark)
}
