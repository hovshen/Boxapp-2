import UIKit
import AVFoundation

class RecognitionViewController: UIViewController, AVCapturePhotoCaptureDelegate {

    // MARK: - @IBOutlets (請確保都已從 Storyboard 正確連結)
    @IBOutlet weak var cameraPreviewView: UIView!
    @IBOutlet weak var identifyButton: UIButton!
    @IBOutlet weak var resultTextView: UITextView!
    
    // MARK: - Gemini API 屬性
    /// MARK: - Gemini API 屬性
    private let geminiAPIKey = "YOUR_API_KEY" // ⚠️ 務必放在安全位置 - 建議使用 Info.plist 或其他方式管理

    // ✅ Adaptive Model Selection
    private var useHighPrecisionModel = false
    private let flashModelURL = URL(string: "https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash-latest:generateContent")!
    private let proModelURL = URL(string: "https://generativelanguage.googleapis.com/v1/models/gemini-2.5-pro-latest:generateContent")!


    // MARK: - AVFoundation 屬性
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var photoOutput: AVCapturePhotoOutput!
    private var initialZoomFactor: CGFloat = 1.0
    private var activityIndicator: UIActivityIndicatorView!

    // MARK: - App 生命週期
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
        listModels()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = cameraPreviewView.bounds
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 當頁面出現時，才開始執行相機
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 當頁面消失時，停止相機以節省電力
        if captureSession?.isRunning == true {
            captureSession.stopRunning()
        }
    }

    // MARK: - @IBActions
    @IBAction func identifyComponentTapped(_ sender: UIButton) {
        // --- UX Enhancement: Haptic Feedback ---
        let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
        impactGenerator.impactOccurred()
        // --- End UX Enhancement ---

        capturePhoto()
    }
    
    // MARK: - 核心功能函式
    
    private func setupUI() {
        // --- UI/UX Overhaul: Programmatic Auto Layout ---

        // 1. Disable autoresizing masks for programmatic constraints
        cameraPreviewView.translatesAutoresizingMaskIntoConstraints = false
        resultTextView.translatesAutoresizingMaskIntoConstraints = false
        identifyButton.translatesAutoresizingMaskIntoConstraints = false

        // 2. Setup Activity Indicator
        activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        // 3. Configure UI elements

        // --- Glassmorphism UI ---
        resultTextView.backgroundColor = .clear
        resultTextView.layer.borderWidth = 0 // Remove border for a cleaner look
        
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 12
        blurView.clipsToBounds = true

        view.insertSubview(blurView, belowSubview: resultTextView)

        // --- End Glassmorphism UI ---

        resultTextView.layer.cornerRadius = 12
        resultTextView.font = UIFont(name: "Avenir Next", size: 17) ?? .systemFont(ofSize: 17)
        resultTextView.isEditable = false
        resultTextView.text = "將電子零件放置於上方框內，然後點擊「辨識零件」按鈕。"
        resultTextView.textColor = .label
        
        identifyButton.setTitle("辨識零件", for: .normal)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.title = "辨識零件"
            config.baseBackgroundColor = .systemBlue
            config.cornerStyle = .medium
            config.buttonSize = .large
            identifyButton.configuration = config
        } else {
            identifyButton.backgroundColor = .systemBlue
            identifyButton.layer.cornerRadius = 8
            identifyButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        }

        // 4. Activate layout constraints
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            // Camera Preview View
            cameraPreviewView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
            cameraPreviewView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            cameraPreviewView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            cameraPreviewView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.4), // 40% of view height

            // Identify Button
            identifyButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -20),
            identifyButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            identifyButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            identifyButton.heightAnchor.constraint(equalToConstant: 50),

            // Result Text View
            resultTextView.topAnchor.constraint(equalTo: cameraPreviewView.bottomAnchor, constant: 16),
            resultTextView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            resultTextView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            resultTextView.bottomAnchor.constraint(equalTo: identifyButton.topAnchor, constant: -16),

            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            // Blur View for Glassmorphism
            blurView.topAnchor.constraint(equalTo: resultTextView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: resultTextView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: resultTextView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: resultTextView.bottomAnchor),
        ])

        // Add pinch-to-zoom gesture
        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchToZoom(_:)))
        cameraPreviewView.addGestureRecognizer(pinchRecognizer)

        // --- Adaptive Model Selection UI ---
        let precisionSwitch = UISwitch()
        precisionSwitch.translatesAutoresizingMaskIntoConstraints = false
        precisionSwitch.addTarget(self, action: #selector(precisionSwitchChanged(_:)), for: .valueChanged)
        view.addSubview(precisionSwitch)

        let precisionLabel = UILabel()
        precisionLabel.translatesAutoresizingMaskIntoConstraints = false
        precisionLabel.text = "高精度模式"
        precisionLabel.font = .systemFont(ofSize: 14)
        view.addSubview(precisionLabel)

        NSLayoutConstraint.activate([
            precisionSwitch.topAnchor.constraint(equalTo: identifyButton.bottomAnchor, constant: 16),
            precisionSwitch.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            precisionLabel.centerYAnchor.constraint(equalTo: precisionSwitch.centerYAnchor),
            precisionLabel.trailingAnchor.constraint(equalTo: precisionSwitch.leadingAnchor, constant: -8),
        ])
        // --- End Adaptive Model Selection UI ---
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo

        guard let backCamera = AVCaptureDevice.default(for: .video) else {
            print("無法使用後置鏡頭")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("設定相機輸入時發生錯誤: \(error.localizedDescription)")
            return
        }

        photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        cameraPreviewView.layer.addSublayer(previewLayer)
    }

    private func capturePhoto() {
        setLoading(true)
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    private func setLoading(_ loading: Bool) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.3) {
                if loading {
                    self.activityIndicator.startAnimating()
                    self.identifyButton.isEnabled = false
                    self.resultTextView.text = "辨識中，請稍候..."
                    self.activityIndicator.alpha = 1.0
                } else {
                    self.activityIndicator.stopAnimating()
                    self.identifyButton.isEnabled = true
                    self.activityIndicator.alpha = 0.0
                }
            }
        }
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            setLoading(false)
            return
        }
        
        // --- Gemini API Optimization: Resize and Compress Image ---
        guard let resizedImage = image.resize(to: CGSize(width: 1024, height: 1024)),
              let compressedImageData = resizedImage.jpegData(compressionQuality: 0.85) else {
            setLoading(false)
            resultTextView.text = "無法調整圖片大小或壓縮圖片"
            return
        }
        // --- End Optimization ---

        let base64Image = compressedImageData.base64EncodedString()
        callGeminiAPI(with: base64Image)
    }

    // MARK: - Gemini API 呼叫
    private func callGeminiAPI(with base64Image: String) {
        let modelURL = useHighPrecisionModel ? proModelURL : flashModelURL
        var request = URLRequest(url: modelURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        // 新增這一行，在請求中加入 App 的 Bundle ID
        request.addValue(Bundle.main.bundleIdentifier!, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        let jsonBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": "請辨識這張圖片中的電子零件，並用繁體中文、條列式的方式提供以下資訊，如果某項資訊不適用或無法辨識，請寫'N/A'：\n1. **零件名稱**: \n2. **規格**: (例如：阻值、電容值、型號)\n3. **適用功率**: \n4. **常見用途**: (用於哪種電路或應用)\n5. **主要功能**: "
                        ],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        let jsonData = try! JSONSerialization.data(withJSONObject: jsonBody)
        request.httpBody = jsonData

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            self.setLoading(false)
            if let error = error {
                DispatchQueue.main.async {
                    self.resultTextView.text = "API 請求失敗: \(error.localizedDescription)"
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.resultTextView.text = "未收到 API 回應資料"
                }
                return
            }

            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let candidates = jsonResponse["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    DispatchQueue.main.async {
                        self.resultTextView.text = text
                    }
                } else {
                    DispatchQueue.main.async {
                        let responseString = String(data: data, encoding: .utf8) ?? "無法解析的回應"
                        self.resultTextView.text = "無法解析 Gemini API 的回應，原始回應：\n\(responseString)"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.resultTextView.text = "解析 API 回應時發生錯誤: \(error.localizedDescription)"
                }
            }
        }
        task.resume()
    }

    // MARK: - Action Handlers
    @objc private func precisionSwitchChanged(_ sender: UISwitch) {
        useHighPrecisionModel = sender.isOn
    }

    // MARK: - Gesture Handling
    @objc private func handlePinchToZoom(_ recognizer: UIPinchGestureRecognizer) {
        guard let device = AVCaptureDevice.default(for: .video) else { return }

        // 確保裝置支援縮放
        let maxZoomFactor = device.activeFormat.videoMaxZoomFactor

        // 計算新的縮放比例
        let newScaleFactor = min(max(recognizer.scale * initialZoomFactor, 1.0), maxZoomFactor)

        switch recognizer.state {
        case .began:
            // 當手勢開始時，記錄當前的縮放比例
            initialZoomFactor = device.videoZoomFactor
        case .changed:
            do {
                // 鎖定裝置設定
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() } // 確保在函式結束時解鎖

                // 更新相機的縮放比例
                device.videoZoomFactor = newScaleFactor
            } catch {
                print("Error locking device for configuration: \(error)")
            }
        default:
            // 手勢結束或取消
            break
        }
    }
    
    private func listModels() {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1/models")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.addValue(self.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        if let bundleID = Bundle.main.bundleIdentifier {
            req.addValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                print("❌ ListModels 錯誤：\(error.localizedDescription)")
                return
            }
            guard let data = data else {
                print("⚠️ ListModels 沒有回傳資料")
                return
            }
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📘 可用模型清單：\n\(jsonString)")
            }
        }
        task.resume()
    }

}

// MARK: - UIImage Extension for Resizing
extension UIImage {
    func resize(to targetSize: CGSize) -> UIImage? {
        let size = self.size

        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height

        // Figure out what our orientation is, and use that to form the rectangle
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }

        // This is the rect that we've calculated out and this is what is actually used below
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)

        // Actually do the resizing to the rect using the ImageContext stuff
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }
}
