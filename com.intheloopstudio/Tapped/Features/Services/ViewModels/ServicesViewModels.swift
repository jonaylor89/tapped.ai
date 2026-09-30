import Foundation
import Observation
import TappedData
import TappedDomain

/// `lib/ui/service_selection/service_selection_view.dart` + the profile "services" section: a user's services.
/// Owners manage them; everyone else picks one to book.
@Observable
@MainActor
final class ServiceListViewModel {
    let userId: String
    let currentUserId: String
    private(set) var services: [Service] = []
    private(set) var user: UserModel?
    private(set) var isLoading = true
    var errorMessage: String?

    private let database: any DatabaseRepository

    init(dependencies: Dependencies, userId: String, currentUserId: String) {
        database = dependencies.database
        self.userId = userId
        self.currentUserId = currentUserId
    }

    var isOwner: Bool { userId == currentUserId }

    func load() async {
        defer { isLoading = false }
        let database = database
        let userId = userId
        async let user = try? await database.getUserById(userId)
        do {
            services = try await database.getUserServices(userId)
        } catch {
            errorMessage = "couldn't load services"
        }
        self.user = await user
    }

    func delete(_ service: Service) async {
        do {
            try await database.deleteService(service.userId, service.id)
            services.removeAll { $0.id == service.id }
        } catch {
            errorMessage = "couldn't delete the service"
        }
    }
}

/// `lib/ui/services/service_view.dart`.
@Observable
@MainActor
final class ServiceDetailViewModel {
    private(set) var service: Service
    private(set) var serviceUser: UserModel?
    private(set) var isDeleting = false
    private(set) var isDeleted = false
    var errorMessage: String?
    let currentUserId: String

    private let database: any DatabaseRepository

    init(dependencies: Dependencies, service: Service, serviceUser: UserModel?, currentUserId: String) {
        database = dependencies.database
        self.service = service
        self.serviceUser = serviceUser
        self.currentUserId = currentUserId
    }

    var isOwner: Bool { service.userId == currentUserId }

    func load() async {
        if let latest = try? await database.getServiceById(service.userId, service.id) {
            service = latest
            isDeleted = latest.deleted
        }
        if serviceUser == nil {
            serviceUser = try? await database.getUserById(service.userId)
        }
    }

    func delete() async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await database.deleteService(service.userId, service.id)
            isDeleted = true
            return true
        } catch {
            errorMessage = "couldn't delete the service"
            return false
        }
    }
}

/// `lib/ui/create_service/create_service_cubit.dart`.
@Observable
@MainActor
final class ServiceFormViewModel {
    let existing: Service?
    let ownerId: String
    var title: String
    var description: String
    /// Dollars, as typed.
    var rate: Decimal?
    var rateType: RateType
    private(set) var isSubmitting = false
    var errorMessage: String?

    static let titleLimit = 60
    static let descriptionLimit = 500

    private let database: any DatabaseRepository
    private let makeId: () -> String

    init(dependencies: Dependencies, service: Service?, ownerId: String, makeId: @escaping () -> String = { UUID().uuidString }) {
        database = dependencies.database
        existing = service
        self.ownerId = ownerId
        self.makeId = makeId
        title = service?.title ?? ""
        description = service?.description ?? ""
        rate = service.map { Decimal($0.rate) / 100 }
        rateType = service?.rateType ?? .fixed
    }

    var isEditing: Bool { existing != nil }

    var rateInCents: Int? {
        guard let rate, rate >= 0 else { return nil }
        return NSDecimalNumber(decimal: rate * 100).rounding(accordingToBehavior: nil).intValue
    }

    var validationMessage: String? {
        if title.trimmed.isEmpty { return "add a title" }
        if title.trimmed.count > Self.titleLimit { return "keep the title under \(Self.titleLimit) characters" }
        if description.trimmed.isEmpty { return "add a description" }
        if description.trimmed.count > Self.descriptionLimit { return "keep the description under \(Self.descriptionLimit) characters" }
        if rateInCents == nil { return "enter a rate" }
        return nil
    }

    var canSubmit: Bool { validationMessage == nil && !isSubmitting }

    func save() async -> Service? {
        guard canSubmit, let cents = rateInCents else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        var service = existing ?? Service(id: makeId(), userId: ownerId)
        service.title = title.trimmed
        service.description = description.trimmed
        service.rate = cents
        service.rateType = rateType
        do {
            if isEditing {
                try await database.updateService(service)
            } else {
                try await database.createService(service)
            }
            return service
        } catch {
            errorMessage = "couldn't save the service"
            return nil
        }
    }
}
