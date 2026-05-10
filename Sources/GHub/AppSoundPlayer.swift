import AppKit
import Foundation

enum AppSoundKind {
    case normalFile
    case gitCommit
    case gitPush
    case ciGreen
    case squashMerge

    var resourceName: String {
        switch self {
        case .normalFile:
            return "pen-click"
        case .gitCommit:
            return "git-commit"
        case .gitPush:
            return "git-push"
        case .ciGreen:
            return "ci-green"
        case .squashMerge:
            return "squash-merge"
        }
    }
}

@MainActor
enum AppSoundPlayer {
    private static var sounds: [AppSoundKind: NSSound] = [:]

    static func play(_ kind: AppSoundKind) {
        if sounds[kind] == nil,
           let url = Bundle.module.url(forResource: kind.resourceName, withExtension: "mp3") {
            sounds[kind] = NSSound(contentsOf: url, byReference: false)
        }

        let sound = sounds[kind]
        sound?.stop()
        sound?.currentTime = 0
        sound?.play()
    }
}
