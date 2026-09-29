import SwiftUI
import WidgetKit

@main
struct TappedWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextGigWidget()
        GigNightLiveActivity()
    }
}

enum WidgetStyle {
    static let accent = Color(red: 0, green: 0x86 / 255, blue: 0xCC / 255)
    static let deep = Color(red: 0.02, green: 0.25, blue: 0.45)
}
