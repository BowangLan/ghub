import SwiftUI

struct BreakdownChipsSection: View {
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("\(stagedCount) staged").chip()
            Text("\(unstagedCount) unstaged").chip()
            Text("\(untrackedCount) untracked").chip()
            Spacer(minLength: 0)
        }
    }
}
