//
//  ContentView.swift
//  Build
//
//  Created by Sergey Zinchenko on 29.12.2023.
//

import SwiftUI
import AVFoundation

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var audioRecorderManager = AudioRecorderManager()
    @State private var logMessages: String = ""

    var body: some View {
        Spacer(minLength: 32)
        Text("Recording App")
            .font(.largeTitle)
        VStack {
            ScrollView {
                TextEditor(text: $logMessages)
                    .frame(height: 300)
                    .padding()
                    .disabled(true)
            }
            
            Button("Start Recording") {
                audioRecorderManager.startRecording()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            
            Button("Pause Recording") {
                audioRecorderManager.pauseRecording()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(4)
            
            Button("Stop Recording") {
                audioRecorderManager.stopRecording()
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
            .padding()
            Spacer(minLength: 32)
        }
        .onAppear {
            audioRecorderManager.setupRecorder()
        }
        .onReceive(audioRecorderManager.$log) { log in
            logMessages += log + "\n"
        }
    }
}


struct PillButtonStyle: ButtonStyle {
    var backgroundColor: Color

    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 25)
                            .fill(backgroundColor))
            .foregroundColor(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.white, lineWidth: configuration.isPressed ? 1 : 0)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(), value: configuration.isPressed)
    }
}

    func startMonitoringAudio() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let url = URL(fileURLWithPath: "/dev/null", isDirectory: true)
        let settings: [String: Any] = [
            AVFormatIDKey: NSNumber(value: kAudioFormatAppleLossless),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]

        audioRecorder = try? AVAudioRecorder(url: url, settings: settings)
        audioRecorder.isMeteringEnabled = true
        audioRecorder.record()

        timer = Timer.publish(every: 0.1, on: .main, in: .common)
        timer.connect().cancel()

        _ = timer.sink { _ in
            self.audioRecorder.updateMeters()
            let power = self.audioRecorder.averagePower(forChannel: 0)
            self.scale = CGFloat(power) / 20.0
        }
}

// MARK: - AudioRecorderManager
class AudioRecorderManager: NSObject, ObservableObject {
    var audioRecorder: AVAudioRecorder?
    @Published var log: String = ""
    var isRecordingPausedByInterruption = false

    func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            appendToLog("Failed to configure audio session: \(error)")
        }
    }
    
    func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    // NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption), name: AVAudioSession.interruptionNotification, object: nil)

    @objc func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            appendToLog("Failed to get interruption type")
            return
        }

        switch type {
        case .began:
            pauseRecording()
            appendToLog("Interruption began")

        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resumeRecording()
                }
            }
            appendToLog("Interruption ended")

        default: break
        }
    }
    
    func setupRecorder() {
        configureAudioSession()
        setupNotifications()
        
        let fileManager = FileManager.default
        let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFileName = docsDir.appendingPathComponent("testRecording.m4a")

        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioFileName, settings: settings)
            audioRecorder?.prepareToRecord()
        } catch {
            appendToLog("Audio recorder setup failed: \(error)")
        }
    }
    
    func startRecording() {
        audioRecorder?.record()
        isRecordingPausedByInterruption = false
        appendToLog("Recording started")
    }
    
    func pauseRecording() {
        audioRecorder?.pause()
        isRecordingPausedByInterruption = true
        appendToLog("Recording paused")
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        isRecordingPausedByInterruption = false
        appendToLog("Recording stopped")
    }
    
    func resumeRecording() {
        if isRecordingPausedByInterruption {
            startRecording()
            appendToLog("Recording resumed")
        }
    }
    
    func appendToLog(_ message: String) {
        DispatchQueue.main.async {
            self.log += message + "\n"
            print(message)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
