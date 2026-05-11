import AVFoundation
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
    private static let soundEffectVolume: Float = 0.3
    private static var players: [AppSoundKind: AVAudioPlayer] = [:]

    static func play(_ kind: AppSoundKind) {
        if players[kind] == nil,
           let url = Bundle.module.url(forResource: kind.resourceName, withExtension: "mp3") {
            players[kind] = try? AVAudioPlayer(contentsOf: url)
            players[kind]?.prepareToPlay()
        }

        let player = players[kind]
        player?.stop()
        player?.currentTime = 0
        player?.volume = soundEffectVolume
        player?.play()
    }
}
