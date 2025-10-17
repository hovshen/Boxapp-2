import UIKit
import AVFoundation

class RecognitionViewController: UIViewController, AVCapturePhotoCaptureDelegate {

    // MARK: - @IBOutlets (請確保都已從 Storyboard 正確連結)
    @IBOutlet weak var cameraPreviewView: UIView!
    @IBOutlet weak var identifyButton: UIButton!
    @IBOutlet weak var resultTextView: UITextView!
    
    // MARK: - Gemini API 屬性
    /// MARK: - Gemini API 屬性
    private let geminiAPIKey = "AIzaSyBlcA7MPvTV7gnkdh1vKLGSXI_2e3z4xYo" // ⚠️ 務必放在安全位置

    // ✅ 使用 v1beta + gemini-1.5-pro
    private let geminiURL = URL(string: "https://generativelanguage.googleapis.com/v1/models/gemini-2.5-pro:generateContent")!


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
        capturePhoto()
    }
    
    // MARK: - 核心功能函式
    
    private func setupUI() {
        // 設定讀取中的指示器
        activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.center = view.center
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        
        resultTextView.layer.borderWidth = 1
        resultTextView.layer.borderColor = UIColor.lightGray.cgColor
        resultTextView.layer.cornerRadius = 8
        resultTextView.text = "將電子零件放置於上方框內，然後點擊「辨識零件」按鈕。"
        
        // --- 從這裡開始加入 ---
            // 建立一個雙指縮放手勢辨識器
            let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchToZoom(_:)))
            // 將手勢辨識器加到相機預覽的畫面上
            cameraPreviewView.addGestureRecognizer(pinchRecognizer)
            // --- 加入到這裡結束 ---
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
            if loading {
                self.activityIndicator.startAnimating()
                self.identifyButton.isEnabled = false
                self.resultTextView.text = "辨識中，請稍候..."
            } else {
                self.activityIndicator.stopAnimating()
                self.identifyButton.isEnabled = true
            }
        }
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation() else {
            setLoading(false)
            return
        }
        
        let base64Image = imageData.base64EncodedString()
        callGeminiAPI(with: base64Image)
    }

    // MARK: - Gemini API 呼叫
    private func callGeminiAPI(with base64Image: String) {
        var request = URLRequest(url: geminiURL)
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
