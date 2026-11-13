import Foundation
import AVFoundation
import CoreVideo
import simd

protocol LiDARCaptureDelegate: AnyObject {
    func onSynchronizedFrame(
        rgbBuffer: CVPixelBuffer,
        depthBuffer: CVPixelBuffer?,
        intrinsics: matrix_float3x3
    )
}

/// Gestionnaire de capture vidéo + LiDAR directement inspiré de iLiDAR (AVCamLiDAR)
final class LiDARCaptureManager: NSObject {

    weak var delegate: LiDARCaptureDelegate?

    private let captureSession = AVCaptureSession()
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private var depthDataOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private let sessionQueue = DispatchQueue(label: "com.gabaritscan.lidar.session")
    private let dataQueue = DispatchQueue(label: "com.gabaritscan.lidar.data", qos: .userInteractive)

    private(set) var isLiDARAvailable = false
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    override init() {
        super.init()
    }

    func setupSession(completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let success = self.configureCaptureSession()
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    private func configureCaptureSession() -> Bool {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .inputPriority

        // 1. Recherche prioritaire de la caméra LiDAR (comme dans iLiDAR)
        var selectedDevice: AVCaptureDevice? = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)

        if selectedDevice != nil {
            isLiDARAvailable = true
            print("🟢 iLiDAR : Caméra .builtInLiDARDepthCamera trouvée !")
        } else {
            isLiDARAvailable = false
            print("⚠️ Caméra LiDAR standard introuvable, bascule sur caméra grand angle")
            selectedDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }

        guard let device = selectedDevice,
              let deviceInput = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(deviceInput) else {
            print("❌ Impossible de créer l'entrée caméra")
            return false
        }

        captureSession.addInput(deviceInput)

        // 2. Sélection du format vidéo + profondeur Float16 (comme dans iLiDAR)
        if isLiDARAvailable {
            let preferredWidth = 1920
            if let format = (device.formats.last { f in
                f.formatDescription.dimensions.width == preferredWidth &&
                f.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange &&
                !f.isVideoBinned &&
                !f.supportedDepthDataFormats.isEmpty
            }),
            let depthFormat = (format.supportedDepthDataFormats.last { df in
                df.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_DepthFloat16
            }) {
                do {
                    try device.lockForConfiguration()
                    device.activeFormat = format
                    device.activeDepthDataFormat = depthFormat
                    device.unlockForConfiguration()
                    print("✅ Format LiDAR actif : \(format.formatDescription.dimensions.width)x\(format.formatDescription.dimensions.height), Profondeur Float16")
                } catch {
                    print("⚠️ Erreur lockForConfiguration : \(error)")
                }
            }
        }

        // 3. Sortie vidéo RGB
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true

        guard captureSession.canAddOutput(videoDataOutput) else { return false }
        captureSession.addOutput(videoDataOutput)

        if let connection = videoDataOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            if connection.isCameraIntrinsicMatrixDeliverySupported {
                connection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }

        // 4. Sortie LiDAR Depth Data (si disponible)
        if isLiDARAvailable {
            depthDataOutput.isFilteringEnabled = true
            if captureSession.canAddOutput(depthDataOutput) {
                captureSession.addOutput(depthDataOutput)
                if let depthConnection = depthDataOutput.connection(with: .depthData) {
                    depthConnection.videoOrientation = .portrait
                }

                // Synchroniseur vidéo + profondeur (même logique qu'iLiDAR)
                synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [depthDataOutput, videoDataOutput])
                synchronizer?.setDelegate(self, queue: dataQueue)
            }
        } else {
            // Mode sans LiDAR : vidéo classique
            videoDataOutput.setSampleBufferDelegate(self, queue: dataQueue)
        }

        return true
    }
}

// MARK: - Synchronisation Vidéo + LiDAR (comme dans iLiDAR)

extension LiDARCaptureManager: AVCaptureDataOutputSynchronizerDelegate {

    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        guard let syncedVideo = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData,
              let rgbBuffer = syncedVideo.sampleBuffer.imageBuffer else { return }

        var depthBuffer: CVPixelBuffer? = nil
        var intrinsics = matrix_float3x3()

        if let syncedDepth = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData {
            depthBuffer = syncedDepth.depthData.depthDataMap
            if let calib = syncedDepth.depthData.cameraCalibrationData {
                intrinsics = calib.intrinsicMatrix
            }
        }

        // Si intrinsèques non disponibles dans calib, lire depuis les attachments du buffer
        if intrinsics[0][0] == 0 {
            intrinsics = matrix_float3x3(
                SIMD3(2870, 0, 0),
                SIMD3(0, 2870, 0),
                SIMD3(Float(CVPixelBufferGetWidth(rgbBuffer))/2, Float(CVPixelBufferGetHeight(rgbBuffer))/2, 1)
            )
        }

        delegate?.onSynchronizedFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: depthBuffer,
            intrinsics: intrinsics
        )
    }
}

// MARK: - Fallback Caméra classique (si pas de LiDAR)

extension LiDARCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let rgbBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let defaultIntrinsics = matrix_float3x3(
            SIMD3(2870, 0, 0),
            SIMD3(0, 2870, 0),
            SIMD3(Float(CVPixelBufferGetWidth(rgbBuffer))/2, Float(CVPixelBufferGetHeight(rgbBuffer))/2, 1)
        )

        delegate?.onSynchronizedFrame(
            rgbBuffer: rgbBuffer,
            depthBuffer: nil,
            intrinsics: defaultIntrinsics
        )
    }
}
