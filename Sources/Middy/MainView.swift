import SwiftUI

struct MainView: View {
    @ObservedObject var model: MiddyModel

    var body: some View {
        PianoRoll(model: model)
            .ignoresSafeArea()
    }
}
