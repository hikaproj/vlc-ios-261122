# VLC Ultimate Engine (`VLCUltimateEngine`)
## 統合ガイド ＆ ビルド設定マニュアル（Step 6: 全結合）

本ドキュメントは、オープンソースの `vlc-ios`（`MobileVLCKit` / Objective-C & Swift混在プロジェクト）に対して、既存コードを一切破壊しない**完全疎結合プラグイン形式**で `VLCUltimateEngine` を統合・ビルドするための完全仕様書です。

---

### 1. ディレクトリ構造

すべてのエンジンコードは `Sources/VLCUltimateEngine/` 配下に完全配置されています：

```
Sources/VLCUltimateEngine/
├── Core/
│   ├── VLCUltimateEngineHookable.swift           # 疎結合プロトコル ＆ 通知ハブ
│   ├── UltimateResourceCoordinator.swift          # Jetsam 850MB制限 ＆ サーマル調停
│   ├── VLCUltimateEngineBridge.swift              # PlaybackService連携ブリッジ
│   └── VLCPlayerViewController+UltimateEngine.swift# PlayerViewController拡張
├── Audio/
│   ├── UltimateAudioBridge.h                      # リアルタイム C-ABI 境界ヘッダ
│   ├── UltimateLockFreeRingBuffer.hpp             # alignas(64) SPSC Lock-Free ループバッファ
│   ├── UltimateLockFreeRingBuffer.cpp             # SPSC実装 ＆ リップシンク群遅延計算
│   ├── UltimateRingBuffer.swift                   # @_silgen_name Swiftラッパー
│   ├── UltimateAudioDSPChain.hpp                  # C++17 全機能DSPヘッダ
│   ├── UltimateAudioDSPChain.cpp                  # Sony Walkman / Dolby / AutoEQ / Karaoke DSP実体
│   ├── UltimatePitchAndChordDetector.hpp          # YIN ピッチ ＆ クロマ PCP ヘッダ
│   ├── UltimatePitchAndChordDetector.cpp          # YIN ＆ 72コード辞書照合実装
│   ├── UltimatePitchShifterBridge.hpp             # ピッチシフター ＆ ハモリ生成ヘッダ
│   ├── UltimatePitchShifterBridge.cpp             # グラニュラー伸張 ＆ 3声ハモリ合成
│   └── UltimateAudioEngine.swift                  # Swift 6 オーディオコーディネーター
├── Video/
│   ├── UltimateVideoTypes.h                       # Metal / Swift 共通型定義
│   ├── UltimateVideoShaders.metal                 # 256ビンヒストグラム / ACES / Anime4K / CRT
│   ├── UltimateMetalHeapManager.swift             # MTLHeap 110MB固定テクスチャプール
│   ├── UltimateStabilizationAndDeinterlace.swift  # 16x16マクロブロック手ぶれ補正
│   ├── UltimateVideoPipeline.swift                # CVMetalTextureCache ゼロコピーパイプライン
│   └── UltimateVideoPlayerView.swift              # 2画面ワイプ / ピンチルーペ / ミニマップ
├── Waveform/
│   ├── UltimateWaveformScanner.swift              # AVAssetReader 高速波形スキャン ＆ キャッシュ
│   ├── UltimateWaveformFTS5Database.swift         # SQLite3 FTS5 全文検索データベース
│   └── UltimateWaveformView.swift                 # 60fps キャンバス波形 ＆ ABリピートドラッグ
├── Study/
│   ├── UltimateBilingualSubtitleParser.swift      # 二分探索 O(log N) 二カ国語SRTパーサー
│   ├── UltimateVideoOCREngine.swift               # Vision .accurate 画面内テキストOCR
│   ├── UltimateShadowingAndSpeedTrainer.swift     # シャドーイング録音 ＆ ループ速度トレーナー
│   └── UltimateStudyOverlayView.swift             # 単語タップ内蔵辞書 ＆ 学習オーバーレイ
├── System/
│   ├── UltimateLiveActivityManager.swift          # Live Activities ＆ Dynamic Island
│   ├── UltimateNFCManager.swift                   # CoreNFC NDEF物理タグ連携
│   ├── UltimatePowerAndPiPManager.swift           # 音声専用超省電力モード ＆ 字幕PiP
│   ├── UltimateLocalWebServer.swift               # Network.framework HTTP + RFC 6455 WebSocket
│   └── UltimateMediaExporter.swift                # 無劣化トリミング ＆ オフライン書き出し
├── UI/
│   ├── UltimateDesignSystem.swift                 # スタジオダークルームパレット ＆ 物理スプリング
│   ├── UltimateFluidAuroraView.swift              # vImage 4色抽出 ＆ 64x64流体オーロラ
│   ├── UltimateHapticEngine.swift                 # CoreHaptics ジョグ＆重低音触覚フィードバック
│   ├── UltimateDisplayLinkDriver.swift            # 60Hz ロック CADisplayLink ドライバー
│   └── UltimateAudioMixerUI.swift                 # スタジオミキサー ＆ 2段ピッチバーUI
└── UX/
    ├── UltimateGestureEngine.swift                # 2.0x長押し / コマ送りジョグダイヤル
    ├── UltimateFolderSettingsStore.swift          # ディレクトリ別 SQLite 自動設定復元
    ├── UltimateSecretVaultView.swift              # 電卓偽装 AES-GCM 暗号化保管庫
    └── UltimateSleepFadeoutTimer.swift            # 60秒対数音量フェード ＆ 250Hz LPフィルター
```

---

### 2. Xcode プロジェクト Build Settings 設定

Xcodeの `VLC-iOS.xcodeproj` において、以下のビルド設定を適用してください：

1. **C++17 言語規格の設定**:
   - `CLANG_CXX_LANGUAGE_STANDARD` = `c++17` (`GNU++17` または `C++17`)
   - `CLANG_CXX_LIBRARY` = `libc++`
2. **ヘッダ検索パス (Header Search Paths)**:
   - `HEADER_SEARCH_PATHS` に以下を追加（再帰的）：
     `$(SRCROOT)/Sources/VLCUltimateEngine/**`
3. **Metal コンパイラ設定**:
   - `MTL_ENABLE_DEBUG_INFO` = `NO` (Release)
   - `MTL_FAST_MATH` = `YES`
4. **Swift 厳格並行性**:
   - `SWIFT_STRICT_CONCURRENCY` = `targeted` または `complete` (Swift 6 Ready)
5. **リンクフレームワーク**:
   - `Accelerate.framework` (vDSP, vImage)
   - `Metal.framework`, `MetalKit.framework`
   - `CoreAudio.framework`, `AVFoundation.framework`
   - `CoreHaptics.framework`
   - `Vision.framework`
   - `Network.framework`
   - `CoreNFC.framework`
   - `ActivityKit.framework`
   - `libsqlite3.tbd`

---

### 3. Podfile の変更不要性（Zero Extra Pods）

`VLCUltimateEngine` は、外部ライブラリへの依存を徹底的に排除し、Apple標準のベアメタルフレームワーク（`Accelerate`、`Metal`、`CoreHaptics`、`Network.framework`、`Vision`、`SQLite3`）とモダン C++17 のみで完結しています。
そのため、既存の `Podfile` に新たな Pod を追加する必要はなく、既存のビルド環境を一切汚染しません。

---

### 4. 実行時のワンライナー接続フック

既存の `PlayerViewController` または `VideoPlayerViewController` の `viewDidLoad` にて、以下の1行を呼び出すだけで全36機能が自動的に有効化されます：

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    
    // VLC Ultimate Workstation Engine を結合
    self.attachUltimateEngine()
}
```

このフックにより：
1. `VLCPlaybackService` の再生・停止・曲送りイベントが `UltimateLiveActivityManager` や `UltimateFolderSettingsStore` と自動同期されます。
2. 画面右上にネオンシアン色のスタジオワークステーションアイコンが追加され、タップで全14機能のスタジオDSPミキサーおよび2段採点ピッチバーが立ち上がります。
3. 画面長押しでの一時2.0倍速、精密ジョグダイヤル、二カ国語字幕辞書、電卓偽装シークレットフォルダがシームレスに機能します。
4. Jetsam監視マネージャ（`UltimateResourceCoordinator`）が常時850MB以下のメモリ予算を強制執行し、サーマルスロットリングを完全防止します。
