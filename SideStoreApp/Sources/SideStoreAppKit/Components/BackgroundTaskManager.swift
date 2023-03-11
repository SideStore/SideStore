//
//  BackgroundTaskManager.swift
//  AltStore
//
//  Created by Riley Testut on 6/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import AVFoundation

public final class BackgroundTaskManager {
	public static let shared = BackgroundTaskManager()

    private var isPlaying = false

    private let audioEngine: AVAudioEngine
    private let player: AVAudioPlayerNode
    private let audioFile: AVAudioFile

    private let audioEngineQueue: DispatchQueue

    private init() {
        audioEngine = AVAudioEngine()
        audioEngine.mainMixerNode.outputVolume = 0.0

        player = AVAudioPlayerNode()
        audioEngine.attach(player)

        do {
            let audioFileURL = Bundle.main.url(forResource: "Silence", withExtension: "m4a")!

            audioFile = try AVAudioFile(forReading: audioFileURL)
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: audioFile.processingFormat)
        } catch {
            fatalError("Error. \(error)")
        }

        audioEngineQueue = DispatchQueue(label: "com.altstore.BackgroundTaskManager")
    }
}

public extension BackgroundTaskManager {
    func performExtendedBackgroundTask(taskHandler: @escaping ((Result<Void, Error>, @escaping () -> Void) -> Void)) {
        func finish() {
            player.stop()
            audioEngine.stop()

            isPlaying = false
        }

        audioEngineQueue.sync {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
                try AVAudioSession.sharedInstance().setActive(true)

                // Schedule audio file buffers.
                self.scheduleAudioFile()
                self.scheduleAudioFile()

                let outputFormat = self.audioEngine.outputNode.outputFormat(forBus: 0)
                self.audioEngine.connect(self.audioEngine.mainMixerNode, to: self.audioEngine.outputNode, format: outputFormat)

                try self.audioEngine.start()
                self.player.play()

                self.isPlaying = true

                taskHandler(.success(())) {
                    finish()
                }
            } catch {
                taskHandler(.failure(error)) {
                    finish()
                }
            }
        }
    }
}

private extension BackgroundTaskManager {
    func scheduleAudioFile() {
        player.scheduleFile(audioFile, at: nil) {
            self.audioEngineQueue.async {
                guard self.isPlaying else { return }
                self.scheduleAudioFile()
            }
        }
    }
}
