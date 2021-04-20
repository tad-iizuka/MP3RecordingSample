//
//  ViewController.swift
//  MP3RecordingSample
//
//  Created by Tadashi on 2017/10/13.
//  Copyright © 2017 UBUNIFU Inc. All rights reserved.
//

import UIKit
import AVFoundation
import AudioToolbox

class ViewController: UIViewController {

	@IBOutlet weak var indicatorView: UIActivityIndicatorView!
	var audioEngine : AVAudioEngine!
	var audioFile : AVAudioFile!
	var audioPlayer : AVAudioPlayerNode!
	var outref: ExtAudioFileRef?
	var audioFilePlayer: AVAudioPlayerNode!
	var mixer : AVAudioMixerNode!
	var filePath : String? = nil
	var filePathMP3: String? = nil
	var isPlay = false
	var isRec = false
	var isMP3Active = false
	var sdate: Date!

	@IBOutlet weak var segment: UISegmentedControl!
	@IBAction func segment(_ sender: Any) {
	}
	
	@IBOutlet var play: UIButton!
	@IBAction func play(_ sender: Any) {

		if self.isPlay {
			self.play.setTitle("PLAY", for: .normal)
			self.indicator(value: false)
			self.stopPlay()
			self.rec.isEnabled = true
		} else {
			if self.startPlay() {
				self.rec.isEnabled = false
				self.play.setTitle("STOP", for: .normal)
				self.indicator(value: true)
			}
		}
	}

	@IBOutlet var rec: UIButton!
	@IBAction func rec(_ sender: Any) {
	
		if self.isRec {
			self.rec.setTitle("RECORDING", for: .normal)
			self.indicator(value: false)
			self.stopRecord()
			self.play.isEnabled = true
		} else {
			self.play.isEnabled = false
			self.rec.setTitle("STOP", for: .normal)
			self.indicator(value: true)
			self.startRecord()
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		self.audioEngine = AVAudioEngine()
		self.audioFilePlayer = AVAudioPlayerNode()
		self.mixer = AVAudioMixerNode()
		self.audioEngine.attach(audioFilePlayer)
		self.audioEngine.attach(mixer)

		self.indicator(value: false)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if AVCaptureDevice.authorizationStatus(for: AVMediaType.audio) != .authorized {
			AVCaptureDevice.requestAccess(for: AVMediaType.audio,
				completionHandler: { (granted: Bool) in
			})
		}
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
	}

	func startRecord() {

		self.isRec = true
		self.filePath = nil

		try! AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord)
		try! AVAudioSession.sharedInstance().setActive(true)

		let format = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatInt16,
			sampleRate: 48000.0,
			channels: 1,
			interleaved: true)

		self.audioEngine.connect(self.audioEngine.inputNode, to: self.mixer, format: format)
		self.audioEngine.connect(self.mixer, to: self.audioEngine.mainMixerNode, format: format)

		let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! as String
		self.filePath =  dir.appending("/temp.wav")

		_ = ExtAudioFileCreateWithURL(URL(fileURLWithPath: self.filePath!) as CFURL,
			kAudioFileWAVEType,
			(format?.streamDescription)!,
			nil,
			AudioFileFlags.eraseFile.rawValue,
			&outref)

		self.mixer.installTap(onBus: 0, bufferSize: AVAudioFrameCount((format?.sampleRate)!), format: format, block: { (buffer: AVAudioPCMBuffer!, time: AVAudioTime!) -> Void in

			let audioBuffer : AVAudioBuffer = buffer
			_ = ExtAudioFileWrite(self.outref!, buffer.frameLength, audioBuffer.audioBufferList)
		})

		try! self.audioEngine.start()
		self.startMP3Rec(path: self.filePath!, rate: 128)
	}

	func stopRecord() {
		self.isRec = false

		self.audioFilePlayer.stop()
		self.audioEngine.stop()
		self.mixer.removeTap(onBus: 0)

		self.stopMP3Rec()
		ExtAudioFileDispose(self.outref!)

		try! AVAudioSession.sharedInstance().setActive(false)
	}

	func startPlay() -> Bool {
	
		if self.filePath == nil {
			return	false
		}

		self.isPlay = true

		try! AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
		try! AVAudioSession.sharedInstance().setActive(true)

		var path = self.filePath
		if self.segment.selectedSegmentIndex == 1 {
			path = self.filePathMP3
		}
		self.audioFile = try! AVAudioFile(forReading: URL(fileURLWithPath: path!))

		self.audioEngine.connect(self.audioFilePlayer, to: self.audioEngine.mainMixerNode, format: audioFile.processingFormat)

		self.audioFilePlayer.scheduleSegment(audioFile,
			startingFrame: AVAudioFramePosition(0),
			frameCount: AVAudioFrameCount(self.audioFile.length),
			at: nil,
			completionHandler: self.completion)

		self.sdate = Date()
		print(self.audioFile.length)
		try! self.audioEngine.start()
		self.audioFilePlayer.play()

		return true
	}
	
	func stopPlay() {
		self.isPlay = false
		if self.audioFilePlayer != nil && self.audioFilePlayer.isPlaying {
			self.audioFilePlayer.stop()
		}
		self.audioEngine.stop()
		let elapsed = Date().timeIntervalSince(self.sdate)
		print(elapsed)
		try! AVAudioSession.sharedInstance().setActive(false)
	}

	func completion() {
		if self.isRec {
			DispatchQueue.main.async {
				self.rec(UIButton())
			}
		} else if self.isPlay {
			DispatchQueue.main.async {
				self.play(UIButton())
			}
		}
	}
	
	func indicator(value: Bool) {
		DispatchQueue.main.async {
			if value {
				self.indicatorView.backgroundColor = UIColor.lightGray
				if self.isRec {
					self.indicatorView.backgroundColor = UIColor.red
				}
				self.indicatorView.startAnimating()
				self.indicatorView.isHidden = false
			} else {
				self.indicatorView.stopAnimating()
				self.indicatorView.isHidden = true
			}
		}
	}

	func startMP3Rec(path: String, rate: Int32) {

		self.isMP3Active = true
		var total = 0
		var read = 0
		var write: Int32 = 0

		let mp3path = path.replacingOccurrences(of: "wav", with: "mp3")
		var pcm: UnsafeMutablePointer<FILE> = fopen(path, "rb")
		fseek(pcm, 4*1024, SEEK_CUR)
		let mp3: UnsafeMutablePointer<FILE> = fopen(mp3path, "wb")
		let PCM_SIZE: Int = 8192
		let MP3_SIZE: Int32 = 8192
		let pcmbuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(PCM_SIZE*2))
		let mp3buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MP3_SIZE))

		let lame = lame_init()
		lame_set_num_channels(lame, 1)
		lame_set_mode(lame, MONO)
		lame_set_in_samplerate(lame, 48000)
		lame_set_brate(lame, rate)
		lame_set_VBR(lame, vbr_off)
		lame_init_params(lame)

		DispatchQueue.global(qos: .default).async {
			while true {
				pcm = fopen(path, "rb")
				fseek(pcm, 4*1024 + total, SEEK_CUR)
				read = fread(pcmbuffer, MemoryLayout<Int16>.size, PCM_SIZE, pcm)
				if read != 0 {
					write = lame_encode_buffer(lame, pcmbuffer, nil, Int32(read), mp3buffer, MP3_SIZE)
					fwrite(mp3buffer, Int(write), 1, mp3)
					total += read * MemoryLayout<Int16>.size
					fclose(pcm)
				} else if !self.isMP3Active {
					_ = lame_encode_flush(lame, mp3buffer, MP3_SIZE)
					_ = fwrite(mp3buffer, Int(write), 1, mp3)
					break
				} else {
					fclose(pcm)
					usleep(50)
				}
			}
			lame_close(lame)
			fclose(mp3)
			fclose(pcm)
			self.filePathMP3 = mp3path
		}
	}
	
	func stopMP3Rec() {
		self.isMP3Active = false
	}
}
