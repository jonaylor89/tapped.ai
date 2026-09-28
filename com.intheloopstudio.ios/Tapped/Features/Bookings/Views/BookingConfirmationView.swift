import SwiftUI
import TappedDomain
import TappedUI

/// Port of `lib/ui/create_booking/booking_confirmation_view.dart`.
struct BookingConfirmationView: View {
    let booking: Booking
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: TappedSpacing.xl) {
            Spacer()
            ConfirmationHero(
                "booking requested",
                message: "your booking will be confirmed once the performer accepts. we'll email you the next steps."
            )
            BookingCard(booking: booking, counterpart: nil)
            Spacer()
            VStack(spacing: TappedSpacing.sm) {
                Button {
                    router.push(.booking(booking))
                } label: {
                    Text("view booking").frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(.horizontal, GlassMetrics.edgeInset)
                GlassSubmitButton("done") { finish() }
            }
        }
        .padding(.horizontal, GlassMetrics.edgeInset)
        .frame(maxWidth: .infinity)
        .background(TappedColors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func finish() {
        while let last = router.path.last, last.isBookingFlowStep { router.pop() }
    }
}

#Preview("booking confirmation") {
    BookingConfirmationView(booking: Samples.bookings[2]).bookingsPreview()
}

#Preview("booking confirmation dark") {
    BookingConfirmationView(booking: Samples.bookings[2]).bookingsPreview(dark: true)
}
