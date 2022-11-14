//
//  MusicViewModel.swift
//  RelaxOn
//
//  Created by hyunho lee on 5/25/22.
//

import SwiftUI
import AVFoundation
import MediaPlayer
import WatchConnectivity

final class MusicViewModel: NSObject, ObservableObject {
    private let playMessageKey = "player"
    private let volumeMessageKey = "volume"
    private let titleMessageKey = "title"
    @Published var currentTitle = ""
    @Published var initiatedByWatch = false
    @Published var isMusicViewPresented = false
    @Published var userRepositoriesState: [MixedSound] = []
    
    override init() {
        super.init()
//        if let data = UserDefaultsManager.shared.CDList {
//            do {
//                let decoder = JSONDecoder()
//                self.userRepositoriesState = try decoder.decode([MixedSound].self, from: data)
//                
//                // TODO: - 추후 다른 방식으로 수정
//                self.sendMessage(key: "list", userRepositoriesState.map{mixedSound in mixedSound.name})
//            } catch {
//                print("Unable to Decode Note (\(error))")
//            }
//        }
        subscribe()
        
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            
            WCSession.default.activate()
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc func appWillTerminate() {
        WidgetManager.closeApp()
        WidgetManager.setupTimerToLockScreendWidget(settedSeconds: 0)
    }
    
    func sendMessage(key: String, _ message: Any) {
        guard WCSession.default.activationState == .activated else {
            return
        }
        
        guard WCSession.default.isWatchAppInstalled else {
            return
        }
        
        WCSession.default.sendMessage([key : message], replyHandler: nil) { error in
            print("Cannot send volume message: \(String(describing: error))")
        }
    }
    
    @Published var baseAudioManager = AudioManager()
    @Published var melodyAudioManager = AudioManager()
    @Published var whiteNoiseAudioManager = AudioManager()
    @Published var isPlaying: Bool = true
    
    @Published var mixedSound: MixedSound? {
        didSet {
            if oldValue?.name != mixedSound?.name {
                startPlayer()
            }
        }
    }
    
    func updateVolume(audioVolumes: (baseVolume: Float, melodyVolume: Float, whiteNoiseVolume: Float)) {
        self.mixedSound?.baseSound?.audioVolume = audioVolumes.baseVolume
        self.mixedSound?.melodySound?.audioVolume = audioVolumes.melodyVolume
        self.mixedSound?.whiteNoiseSound?.audioVolume = audioVolumes.whiteNoiseVolume
    }
    
    func changeMixedSound(mixedSound: MixedSound) {
        self.mixedSound = mixedSound
    }
    
    func fetchData(data: MixedSound) {
        mixedSound = data
        guard let mixedSound = mixedSound else { return }
        self.setupRemoteCommandCenter()
        self.setupRemoteCommandInfoCenter(mixedSound: mixedSound)
    }
    
    func playPause() {
        baseAudioManager.playPause()
        melodyAudioManager.playPause()
        whiteNoiseAudioManager.playPause()
        self.isPlaying.toggle()
        
        self.sendMessage(key: playMessageKey, self.isPlaying ? "play" : "pause")
        self.sendMessage(key: titleMessageKey, self.mixedSound?.name ?? "")
        saveWidgetData()
    }
    
    func stop() {
        baseAudioManager.stop()
        melodyAudioManager.stop()
        whiteNoiseAudioManager.stop()
        
        self.sendMessage(key: playMessageKey, "pause")
        self.sendMessage(key: titleMessageKey, self.mixedSound?.name ?? "")
        saveWidgetData()
    }
    
    func startPlayer() {
        self.currentTitle = mixedSound?.name ?? ""
        
        baseAudioManager.startPlayer(track: mixedSound?.baseSound?.fileName ?? "base_default", volume: mixedSound?.baseSound?.audioVolume ?? 0.8)
        melodyAudioManager.startPlayer(track: mixedSound?.melodySound?.fileName ?? "base_default", volume: mixedSound?.melodySound?.audioVolume ?? 0.8)
        whiteNoiseAudioManager.startPlayer(track: mixedSound?.whiteNoiseSound?.fileName ?? "base_default", volume: mixedSound?.whiteNoiseSound?.audioVolume ?? 0.8)
        
        self.isPlaying = true
        
        self.sendMessage(key: playMessageKey, "play")
        self.sendMessage(key: titleMessageKey, self.mixedSound?.name ?? "")
        saveWidgetData()
    }
    
    func startPlayerFromWatch() {
        
        let index = self.userRepositoriesState.firstIndex { element in
            element.name == self.currentTitle
        }
        
        guard let idx = index else { return }
        self.mixedSound = self.userRepositoriesState[idx]
        guard let mixedSound = self.mixedSound else { return }
        
        self.isPlaying = true
        
        baseAudioManager.startPlayer(track: mixedSound.baseSound?.fileName ?? "base_default", volume: mixedSound.baseSound?.audioVolume ?? 0.8)
        melodyAudioManager.startPlayer(track: mixedSound.melodySound?.fileName ?? "base_default", volume: mixedSound.melodySound?.audioVolume ?? 0.8)
        whiteNoiseAudioManager.startPlayer(track: mixedSound.whiteNoiseSound?.fileName ?? "base_default", volume: mixedSound.whiteNoiseSound?.audioVolume ?? 0.8)
        
        self.setupRemoteCommandCenter()
        self.setupRemoteCommandInfoCenter(mixedSound: mixedSound)
    }
    
    func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()
        
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        guard let mixedSound = self.mixedSound else { return }
        
        center.playCommand.addTarget { commandEvent -> MPRemoteCommandHandlerStatus in
            self.playPause()
            self.sendMessage(key: self.playMessageKey, self.isPlaying ? "play" : "pause")
            self.sendMessage(key: self.titleMessageKey, self.mixedSound?.name ?? "")
            return .success
        }
        
        center.pauseCommand.addTarget { commandEvent -> MPRemoteCommandHandlerStatus in
            self.playPause()
            self.sendMessage(key: self.playMessageKey, self.isPlaying ? "play" : "pause")
            self.sendMessage(key: self.titleMessageKey, self.mixedSound?.name ?? "")
            return .success
        }
        
        center.nextTrackCommand.addTarget { MPRemoteCommandEvent in
            self.setupNextTrack(mixedSound: mixedSound)
            return .success
        }
        
        center.previousTrackCommand.addTarget { MPRemoteCommandEvent in
            self.setupPreviousTrack(mixedSound: mixedSound)
            return .success
        }
    }
    
    func setupRemoteCommandInfoCenter(mixedSound: MixedSound) {
        let center = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = center.nowPlayingInfo ?? [String: Any]()
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = mixedSound.name
        if let albumCoverPage = UIImage(named: mixedSound.baseSound?.fileName ?? "") {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: albumCoverPage.size, requestHandler: { size in
                return albumCoverPage
            })
        }
        // MARK: - 타이머 연동돌 때 건드릴 코드
        //        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = self.baseAudioManager.player?.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: self.baseAudioManager.player?.currentTime ?? 0.0)
        
        center.nowPlayingInfo = nowPlayingInfo
    }
    
    func setupNextTrack(mixedSound: MixedSound) {
        let count = self.userRepositoriesState.count
        let id = mixedSound.id
        let index = self.userRepositoriesState.firstIndex { element in
            element.name == mixedSound.name
        }
        self.isPlaying = true
        
        if index == count - 1 {
            guard let firstSong = self.userRepositoriesState.first else { return }
            self.mixedSound = firstSong
            self.setupRemoteCommandInfoCenter(mixedSound: firstSong)
            self.setupRemoteCommandCenter()
            
            self.currentTitle = firstSong.name
            self.sendMessage(key: self.titleMessageKey, firstSong.name)
            self.sendMessage(key: self.playMessageKey, "play")
        } else {
            let nextSong = self.userRepositoriesState[ self.userRepositoriesState.firstIndex {
                $0.id > id
            } ?? 0 ]
            self.mixedSound = nextSong
            self.setupRemoteCommandInfoCenter(mixedSound: nextSong)
            self.setupRemoteCommandCenter()
            
            self.currentTitle = nextSong.name
            self.sendMessage(key: self.titleMessageKey, nextSong.name)
            self.sendMessage(key: self.playMessageKey, "play")
        }
    }
    
    func setupPreviousTrack(mixedSound: MixedSound) {
        let id = mixedSound.id
        let index = self.userRepositoriesState.firstIndex { element in
            element.name == mixedSound.name
        }
        self.isPlaying = true
        
        if index == 0 {
            guard let lastSong = self.userRepositoriesState.last else { return }
            self.mixedSound = lastSong
            self.setupRemoteCommandInfoCenter(mixedSound: lastSong)
            self.setupRemoteCommandCenter()
            
            self.currentTitle = lastSong.name
            self.sendMessage(key: self.titleMessageKey, lastSong.name)
        } else {
            let previousSong = self.userRepositoriesState[ self.userRepositoriesState.lastIndex {
                $0.id < id
            } ?? 0 ]
            self.mixedSound = previousSong
            self.setupRemoteCommandInfoCenter(mixedSound: previousSong)
            self.setupRemoteCommandCenter()
            
            self.currentTitle = previousSong.name
            self.sendMessage(key: self.titleMessageKey, previousSong.name)
        }
    }
    
    @Published var volume: Float = AVAudioSession.sharedInstance().outputVolume
    
    private let audioSession = AVAudioSession.sharedInstance()
    
    private var progressObserver: NSKeyValueObservation!
    
    func subscribe() {
        progressObserver = audioSession.observe(\.outputVolume) { [self] (audioSession, value) in
            DispatchQueue.main.async {
                self.volume = audioSession.outputVolume
                self.sendMessage(key: "volume", audioSession.outputVolume)
            }
        }
    }
    
    // TODO: - 구독 해제하기
    func unsubscribe() {
        self.progressObserver.invalidate()
    }
    
    private func saveWidgetData() {
        if let mixedSound = mixedSound,
           let baseImageName = mixedSound.baseSound?.fileName,
           let melodyImageName = mixedSound.melodySound?.fileName,
           let whiteNoiseImageName = mixedSound.whiteNoiseSound?.fileName {
            WidgetManager.addMainSoundToWidget(
                data: SmallWidgetData(
                    baseImageName: baseImageName,
                    melodyImageName: melodyImageName,
                    whiteNoiseImageName: whiteNoiseImageName,
                    name: mixedSound.name,
                    id: mixedSound.id,
                    isPlaying: isPlaying,
                    isRecentPlay: false
                )
            )
        }
    }
}

// MARK: - WCSessionDelegate
extension MusicViewModel: WCSessionDelegate {
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let state = message[playMessageKey] as? String {
            DispatchQueue.main.async { [weak self] in
                print(state)
                switch state {
                    case "play", "pause":
                        if let isPresented = self?.isMusicViewPresented {
                            if isPresented {
                                self?.playPause()
                            } else {
                                self?.initiatedByWatch = true
                                if (UIApplication.shared.applicationState == .background) {
                                    self?.playPause()
                                }
                            }
                        } else {
                            self?.playPause()
                        }
                    case "prev":
                        guard let mixedSound = self?.mixedSound else { return }
                        self?.setupPreviousTrack(mixedSound: mixedSound)
                    case "next":
                        guard let mixedSound = self?.mixedSound else { return }
                        self?.setupNextTrack(mixedSound: mixedSound)
                    default:
                        print("해당 안됨")
                }
            }
        }
        
        if message["list"] is String {
            DispatchQueue.main.async { [weak self] in
                self?.sendMessage(key: "list", self?.userRepositoriesState.map{mixedSound in mixedSound.name})
                // 원래 있던 친구        self?.sendMessage(key: "list", self.userRepositoriesState.map{mixedSound in mixedSound.name})
            }
        }
        
        if let title = message[titleMessageKey] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.currentTitle = title
                if let isPresented = self?.isMusicViewPresented {
                    if isPresented {
                        self?.startPlayerFromWatch()
                    } else {
                        self?.initiatedByWatch = true
                        self?.startPlayerFromWatch()
                    }
                } else {
                    self?.startPlayerFromWatch()
                }
            }
        }
        
        if let volume = message["changeVolume"] as? String {
            DispatchQueue.main.async { [weak self] in
                if let floatVolume = Float(volume) {
                    SystemVolumeControl.setVolume(volume: floatVolume)
                }
            }
        }
        if message["requestVolume"] is String {
            DispatchQueue.main.async { [weak self] in
                self?.sendMessage(key: "volume", self?.volume)
            }
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
