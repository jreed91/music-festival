import SwiftUI
import WidgetKit

/// Everything this extension vends: the Home and Lock Screen widget, and the Live
/// Activity that ActivityKit draws while a starred set is on.
@main
struct HinterlandWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
        NowPlayingLiveActivity()
    }
}
