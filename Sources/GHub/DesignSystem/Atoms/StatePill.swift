import SwiftUI

struct StatePill: View {
    enum Kind {
        case pr(PullRequest)
        case noPR
        case custom(label: String, color: Color, dot: Bool)
    }
    let kind: Kind

    var body: some View {
        let r = resolve()
        return HStack(spacing: 5) {
            if r.dot {
                Circle().fill(r.color).frame(width: 6, height: 6)
            }
            Text(r.label).font(.system(size: 11, weight: .medium))
        }
        .pill(r.color)
    }

    private func resolve() -> (label: String, color: Color, dot: Bool) {
        switch kind {
        case .pr(let pr):
            if pr.isDraft { return ("Draft", DT.Color.amber, true) }
            switch pr.state.uppercased() {
            case "OPEN":   return ("Open", DT.Color.emerald, true)
            case "MERGED": return ("Merged", DT.Color.sky, true)
            case "CLOSED": return ("Closed", DT.Color.red, true)
            default:       return (pr.state.capitalized, .secondary, true)
            }
        case .noPR:
            return ("No PR", DT.Color.amber, false)
        case .custom(let l, let c, let d):
            return (l, c, d)
        }
    }
}
