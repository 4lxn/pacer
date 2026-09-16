import SwiftUI

struct CoachSheet: View {
    let blocks: [Block]
    let now: Date
    let completed: Set<String>

    var body: some View {
        NavigationStack {
            Text("Coach comes in the next commit.")
                .navigationTitle("Coach")
        }
    }
}
