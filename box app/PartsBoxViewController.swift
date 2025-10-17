import UIKit
import CoreBluetooth // 引用核心藍牙框架

// 讓 ViewController 遵從藍牙和 UITableView 的相關協定
class PartsBoxViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate, UITableViewDelegate, UITableViewDataSource {

    // MARK: - @IBOutlets (UI 元件連結)
    // 確保這些 Outlet 都已從 Storyboard 正確連結
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var statusLabel: UILabel!
    
    // MARK: - 藍牙相關屬性
    private var centralManager: CBCentralManager!
    private var smartBoxPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?

    // 與 ESP32 程式碼中完全相同的 UUID
    let smartBoxServiceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    let commandCharacteristicUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

    // MARK: - 零件資料模型
    // 使用一個字典來儲存所有零件的資料
    let componentData: [String: [String]] = [
        "電阻": ["1K", "2K", "3K"],
        "BJT": ["2N3904", "BC547", "S8050"],
        "MOS": ["IRF540N", "2N7000", "BS170"]
    ]
    // 用於儲存當前列表要顯示的零件
    var currentComponents: [String] = []

    // MARK: - App 生命週期
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 初始化藍牙 Central Manager，並將其代理設為自己
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        // 設定 UITableView 的代理
        tableView.delegate = self
        tableView.dataSource = self
        
        // 初始化 App 畫面
        updateComponentList()
        updateStatus(message: "尚未連線", isConnected: false)
    }

    // MARK: - @IBActions (UI 事件處理)
    @IBAction func segmentedControlChanged(_ sender: UISegmentedControl) {
        // 當分段控制器改變時，更新列表
        updateComponentList()
    }
    
    @IBAction func connectButtonTapped(_ sender: UIButton) {
        // 如果已連線，則斷開；如果未連線，則開始掃描
        if smartBoxPeripheral?.state == .connected {
            disconnectDevice()
        } else {
            startScanning()
        }
    }
    
    // MARK: - 核心功能函式
    
    // 更新零件列表的內容
    func updateComponentList() {
        // 根據 segmented control 選擇的 index 取得對應的分類標題
        guard let category = segmentedControl.titleForSegment(at: segmentedControl.selectedSegmentIndex) else { return }
        // 從字典中取得該分類的零件陣列
        currentComponents = componentData[category] ?? []
        // 重新載入 table view 來顯示新的內容
        tableView.reloadData()
    }
    
    // 更新狀態標籤和按鈕的文字
    func updateStatus(message: String, isConnected: Bool) {
        statusLabel.text = message
        if isConnected {
            connectButton.setTitle("斷開連線", for: .normal)
            connectButton.backgroundColor = .systemRed // 已連線時顯示紅色
        } else {
            connectButton.setTitle("連接智慧零件盒", for: .normal)
            connectButton.backgroundColor = .systemGreen // 未連線時顯示綠色
        }
    }
    
    // 開始掃描指定的藍牙服務
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            updateStatus(message: "藍牙未開啟，請檢查設定", isConnected: false)
            return
        }
        updateStatus(message: "掃描中...", isConnected: false)
        // 開始掃描，只尋找帶有我們指定 Service UUID 的設備
        centralManager.scanForPeripherals(withServices: [smartBoxServiceUUID], options: nil)
    }
    
    // 斷開連線
    func disconnectDevice() {
        if let peripheral = smartBoxPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    // MARK: - CBCentralManagerDelegate (藍牙 Central 核心代理方法)
    
    // 當藍牙狀態改變時（例如：開啟、關閉、未授權）會被呼叫
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // 藍牙已開啟，準備就緒
            updateStatus(message: "藍牙已就緒，請點擊連接", isConnected: false)
        case .poweredOff:
            updateStatus(message: "藍牙已關閉", isConnected: false)
        case .unauthorized:
            updateStatus(message: "未授權使用藍牙", isConnected: false)
        case .unsupported:
            updateStatus(message: "此設備不支援藍牙", isConnected: false)
        default:
            updateStatus(message: "藍牙狀態未知", isConnected: false)
        }
    }
    
    // 當掃描到符合條件的藍牙周邊設備時會被呼叫
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // 停止掃描以節省電力
        centralManager.stopScan()
        // 保存找到的設備
        smartBoxPeripheral = peripheral
        smartBoxPeripheral?.delegate = self
        updateStatus(message: "找到零件盒，連線中...", isConnected: false)
        // 開始連接設備
        centralManager.connect(peripheral, options: nil)
    }
    
    // 當成功連接到設備時會被呼叫
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        updateStatus(message: "✅ 已連線", isConnected: true)
        // 開始尋找設備上的服務 (Service)
        peripheral.discoverServices([smartBoxServiceUUID])
    }
    
    // 當連線失敗時會被呼叫
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        updateStatus(message: "連線失敗", isConnected: false)
    }
    
    // 當設備斷開連線時會被呼叫
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        updateStatus(message: "已斷線", isConnected: false)
        smartBoxPeripheral = nil
        commandCharacteristic = nil
    }

    // MARK: - CBPeripheralDelegate (藍牙 Peripheral 核心代理方法)
    
    // 當找到服務 (Service) 時會被呼叫
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            // 開始尋找服務中的特徵 (Characteristic)
            peripheral.discoverCharacteristics([commandCharacteristicUUID], for: service)
        }
    }
    
    // 當找到特徵 (Characteristic) 時會被呼叫
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == commandCharacteristicUUID {
                // 保存這個特徵，我們將用它來發送指令
                commandCharacteristic = characteristic
                print("已找到指令特徵！準備發送指令。")
            }
        }
    }
    
    // MARK: - UITableViewDataSource & UITableViewDelegate
    
    // 設定列表有幾行
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return currentComponents.count
    }
    
    // 設定每一行的內容
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // 從重用池中取得一個 Cell
        let cell = tableView.dequeueReusableCell(withIdentifier: "ComponentCell", for: indexPath)
        // 設定 Cell 顯示的文字
        cell.textLabel?.text = currentComponents[indexPath.row]
        return cell
    }
    
    // 當使用者點擊列表中的某一行時會被呼叫
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // 取消該行的選中狀態，產生一個點擊效果
        tableView.deselectRow(at: indexPath, animated: true)
        
        // 確保已連線且已找到可以寫入的特徵
        guard let peripheral = smartBoxPeripheral, let characteristic = commandCharacteristic else {
            print("錯誤：尚未連線或未找到特徵，無法發送指令。")
            return
        }
        
        // 取得被點擊的零件名稱
        let componentName = currentComponents[indexPath.row]
        // 將零件名稱（字串）轉換成藍牙傳輸需要的 Data 格式
        guard let data = componentName.data(using: .utf8) else { return }
        
        // 透過藍牙將資料寫入到 ESP32 的特徵中
        // .withResponse 表示需要 ESP32 確認收到，比較可靠
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        
        print("已發送指令：\(componentName)")
    }
}
