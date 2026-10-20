# Apple TV Stride

**在家原地踏步或超慢跑，讓 Apple TV 上的風景隨步伐前進，停下就停。**

Local-first、MIT 開源的 iPhone 控制器＋原生 tvOS App。第一版沒有雲端帳號、訂閱、地圖金鑰或外部素材依賴，內建自製的 3D 林間環狀路線。

> 狀態：可供編譯、測試與實機驗收的 MVP，不是已驗證的成品。請以 PR 最新 commit 的 CI 結果為準；模擬器編譯成功不代表真實步態辨識或裝置間連線已驗證。

## 已實作與尚未實作

| 項目 | 狀態 |
|---|---|
| iPhone Core Motion 50 Hz、垂直加速度投影、步頻與信心估算 | 已實作；須以真實動作校準 |
| 相機掃描 QR / 手動配對、Bonjour 搜尋、TLS-PSK 本機通訊 | 已實作；須驗證實機互通 |
| 10 Hz 控制訊息、有界解析／背壓、重送與跨 session 拒絕 | 已實作、核心狀態機有測試 |
| 停步、過期訊號、斷線及 TV 暫停鎖定 | 已實作、核心狀態機有測試 |
| tvOS 自製 3D 路線、虛擬距離、步頻 HUD | 已實作；不需任何下載 |
| HTTPS 平面影片與單眼 2:1 360° 影片播放 | 已實作；未附第三方影片，需實測媒體相容性 |
| iPhone 明確標示的模擬步頻模式 | 已實作；方便模擬器及連線測試 |
| Apple Watch、HealthKit、心率、鎖屏持續感測 | **尚未實作** |
| Mapillary / Google Street View / Remote Walk API | **尚未接入** |
| GPX / GeoJSON 匯入、OSM 場景生成、路線下載商店 | **尚未實作** |
| App Store 簽章、圖示、TestFlight / 正式發行 | **尚未完成** |

Remote Walk 是先前討論的產品參考，不是本專案的程式庫，也不會被當成素材來源或抓取對象。

## 開發與安裝

需求：macOS、完整 Xcode 16 或更新版本（含 iOS / tvOS SDK）、XcodeGen；目標 iOS 17+、tvOS 17+。

```bash
git clone https://github.com/knowlet/appletv-stride.git
cd appletv-stride
git checkout feat/stride-mvp
brew install xcodegen
xcodegen generate
open Stride.xcodeproj
```

在 Xcode 分別選取 `StridePhone` 與 `StrideTV` scheme，於 Signing & Capabilities 選擇自己的 Team。必要時變更兩個 bundle identifier。將前者安裝至 iPhone、後者安裝至 Apple TV。真實硬體安裝需要對應簽章與裝置設定，CI 產物是**未簽章的模擬器 App**，不能直接裝到實體 Apple TV。

1. iPhone 和 Apple TV 接上同一區域網路，打開 Stride。
2. 在手機允許區域網路、動作與相機權限，掃描 TV 的配對 QR Code；亦可從找到的 TV 輸入 32 位配對碼。
3. 將手機固定在腰部附近或貼身褲袋，點「開始感測」，先測原地踏步、停下、再開始。
4. 遙控器的播放／暫停鍵是獨立暫停鎖；即使持續踏步，也不會覆蓋 TV 的暫停。

**手機必須保持 App 前景。** 感測期間會停用自動鎖定；切到背景、控制中心或鎖屏會停止並斷線，回來後需重新連線。不要把手持任意晃動的辨識結果當成可靠步數。

沒有真實 iPhone 時，可開啟「開發測試 — 非真實運動資料」中的模擬步頻；此模式只驗證連線與場景，不驗證感測器。

## 場景與影片

預設場景使用 SceneKit 的程式化幾何建構，不是從 Google、Mapillary 或其他平台下載。SceneKit 是本 MVP 為支援 tvOS 17+ 所選的隔離渲染實作；未來可以換成較新系統的 RealityKit，而不改動步頻或通訊核心。

在 TV 的「選擇場景」可切換平面影片或 360° 影片，輸入你**有權使用**的 HTTPS MP4 / HLS 網址與拍攝參考速度。套用後保持暫停，須手動恢復。

360° 素材必須是**單眼、2:1 等距柱狀投影**；左右鍵調整觀看方向。定點拍攝只能環視，無法憑空產生向前移動視差。影片模式的倍率範圍是 0.25–2 倍，暫停是 0 倍；倍率截限或緩衝可能讓影片時間與運動累積的虛擬距離不同。這還不是精準 distance-locked 影片播放器。

沒有提供第三方影片，也沒有通用的「CC 授權＝可隨意商用」假設。素材規則見 [docs/ASSETS.md](docs/ASSETS.md)。

## 測試

Linux / macOS 可執行不依賴 Apple SDK 的核心測試：

```bash
bash scripts/verify.sh
```

初次本地驗證：Swift 6.2.1 / Linux，**43 項 XCTest 通過**，含不同步頻、停止與訊號逾時、分包／黏包、超大訊息、版本驗證、配對格式、重送／跨 session、暫停鎖及路線插值。這些是合成資料，不是真人步態測試。Linux 上的 Apple App syntax check 也**不是** Apple SDK type check。

在 macOS 編譯兩個模擬器 App：

```bash
bash scripts/build-apple.sh
```

GitHub Actions 分別執行 portable core 驗證、Apple 工具鏈核心測試與 iOS / tvOS simulator build，保存 SHA 命名的建置日誌及模擬器 App。XcodeGen 由 runner 的 Homebrew 安裝，實際版本會保留於 artifact；目前不宣稱整個建置環境可位元重現。

## 目錄

```text
Sources/StrideCore/     純 Swift：感測估算、封包、播放狀態機、路線
Tests/StrideCoreTests/  無硬體依賴的合成測試
Apps/Shared/           Network.framework / TLS 配對與傳輸
Apps/iPhone/           Core Motion、QR scanner、控制器 UI
Apps/TV/               tvOS UI、SceneKit、AVFoundation
project.yml            XcodeGen 專案來源
scripts/               本機與 CI 驗證入口
docs/                  架構、素材政策與實機驗收
```

## 限制與下一階段

步頻辨識要求至少三個有效峰值，停步偵測依步頻採 0.8–1.8 秒的門檻，再加訊息與呈現延遲；不能承諾「每一步立即同步」。目前針對固定在腰部的手機調整，手腕動作需要另外校準，不能直接拿這組參數套到 Apple Watch。

下一階段是實機連線與步態資料驗收、Watch 感測來源／運動 session、具授權的街景序列 adapter，再考慮離線路線包與 RealityKit。驗收清單見 [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)，安全邊界見 [SECURITY.md](SECURITY.md)。

程式碼與自製的程式化場景採 [MIT](LICENSE)。第三方 SDK、使用者自行載入的影像與資料保持原授權。
