<h3 align="center">
  <a href="https://www.videolan.org/images/vlc-ios/readme_banner.png">
  <img src="https://www.videolan.org/images/vlc-ios/readme_banner.png?raw=true" alt="VLC-iOS banner">
  </a>
</h3>

# VLC Ultimate Workstation Edition (`VLCUltimateEngine`)
> **Customized & Supercharged by [Hikaproj](https://hikaproj.com)**  
> 🌐 **Official Website:** [https://hikaproj.com](https://hikaproj.com)  
> 📩 **Contact & Inquiries:** [https://hikaproj.com/new/contact](https://hikaproj.com/new/contact)  
> 🐦 **X (Twitter):** [@hikaproj](https://x.com/hikaproj)

---

## 🚀 概要 (Overview)
本リポジトリは、オープンソースの `vlc-ios`（`MobileVLCKit` / Objective-C & Swift混在）をベースに、**Hikaproj** の高度なシステムアーキテクチャ設計およびベアメタル音響・映像数理アルゴリズムにより、**「世界最強のローカル専用・次世代メディア＆オーディオワークステーション（`VLCUltimateEngine`）」** として拡張・カスタマイズされた特別版です。

### ⚡ ハードウェア極限最適化（A11 Bionic / 2GB RAM / iOS 16.1+ ターゲット）
- **Jetsam 850MB 厳格メモリ予算保護**: Machカーネル VM API（`task_info(TASK_VM_INFO)`）により `phys_footprint` を常時監視。サーマルスロットリング時（`.serious` / `.critical`）には自動で動的FFT窓縮小（4096→1024）やMetalシェーダーのハーフ精度フォールバック（`RGBA16Float` → `BGRA8Unorm`）を実行。
- **Hard Real-Time Lock-Free オーディオ**: `alignas(64)`（L1キャッシュライン整列）による C++17 SPSC Lock-Free RingBuffer を採用。リアルタイムレンダースレッド内での `malloc` / Swift ARC / Objective-C ディスパッチ / ミューテックスを完全排除。
- **Metal Zero-Copy 映像パイプライン**: `CVMetalTextureCache` ゼロコピーテクスチャ取得、および `MTLHeap`（110MB固定）によるフレーム毎のメモリ確保ゼロ（テクスチャエイリアシング再利用）を達成。
- **60fps ロック ＆ 超低GPU負荷 UI (<1.5%)**: `vImage` 4色パレット抽出と64×64極小オフスクリーン流体シミュレーション＋GPUバイリニア補間により、重たいガウシアンブラーを完全排除しながらシルキーな流体オーロラUIを実現。

---

## 🎛️ 追加機能一覧（全36モジュール詳細）

### Module A: 究極の音響DSP ＆ カラオケ・ピッチ同期エンジン (`UltimateAudioEngine`)
1. **Sony Walkman風 DSEE Ultimate 高域倍音補完**: 8k-16kHzを抽出し、非線形ウェーブシェイピング（半波整流＋3次飽和）で第2・第3倍音を生成、14k-22kHzハイパス通過後に原音へダイナミックブレンド。
2. **Sony Walkman風 バイナルプロセッサー**: トーンアーム共振を模した25Hz微弱ピーキングEQ、偶数次倍音サチュレーション、-82dBFS極微量アナログフロアノイズ。
3. **Sony Walkman風 DCフェーズリニアライザー**: 4〜8段縦続接続2次オールパスIIRフィルター群により、アナログA級アンプの重厚な低音アタック位相を再現。
4. **Dolby風 7.1.4ch 仮想立体音響**: 仮想12スピーカー座標へのHRTFインパルス畳み込み、Schroeder/Moorer型初期反射残響（FDN 4段フィードバック行列）合成。
5. **Dolby風 セリフ明瞭化 (Dialog Enhancer)**: Mid/Side分離後のMid成分から声フォルマント（1k-4kHz）エンベロープを検出し、発話時のみSide成分を-4.5dB自動ダッキング。
6. **AutoEQ 高速テキストパーサー**: 正規表現ゼロのC++パーサーにより、GraphicEQ/ParametricEQテキストから最大10バンドの双二次IIRフィルター係数を瞬時適用。
7. **ナイトモード**: 2ms先行ルックアヘッド型高速RMSコンプレッサー（150msリリース / 8:1レシオ）＋自動メイクアップゲイン。
8. **リアルタイムコード解析 ＆ ウォーターフォールFFT**: 2048点Hanning窓から12半音クロマベクトル（PCP）を算出し、72コード辞書テンプレートとのコサイン類似度でコード名を即座に判定。
9. **重低音 Taptic Engine 連動**: 4次Butterworthローパス（75Hz）通過後のエンベロープ微分からトランジェントを検出し、`CoreHaptics` でリアルタイム重低音振動を出力。
10. **リアルタイム高精度ボーカル除去**: 120Hz以下モノラル低域（キック・ベース）を完全保護し、120Hz〜8kHzの中高域センター定位成分のみを減衰。
11. **精密採点風 2段リアルタイムピッチバー**: 高速 YIN アルゴリズム＋放物線補間（小数精度 $F_0$）により伴奏メロディとマイク音声を同時検出し、ピアノロール上に2段描画＆一致率スコアリング。
12. **自動キー変更 ＆ 歌声オートチューン**: グラニュラー時間伸張による-6〜+6半音キーチェンジ。マイク音声はスケール最近傍ターゲット周波数へ瞬時ピッチ補正。
13. **コード連動自動ハモリ生成**: リアルタイム解析コードに基づき、3度上（長/短自動判定）・3度下・オクターブ下の並列3声を合成。
14. **低遅延マイクエコー ＆ FDNプレートリバーブ**: `AVAudioSession` 5.33ms 超低遅延I/O、ボーカル専用コンプレッサー＋ステレオプレートリバーブ。

### Module B: Metal Zero-Copy カスタム映像パイプライン (`UltimateVideoPipeline`)
15. **Dolby Vision風 動的HDRトーンマッピング**: スレッドグループ共有メモリを用いた256ビン輝度ヒストグラムと、時間平滑化ACES/Reinhardトーンマッピング。
16. **Anime4K風 超解像シャープネス ＆ レトロCRTフィルター**: Sobel勾配エッジ細線化、CASアンチリンギング、走査線・アパーチャグリル・色収差・フィルムグレイン。
17. **2画面同期ワイプ比較プレイヤー**: 画面分割座標 `splitX`（0.0〜1.0）によるA/Bリアルタイム比較描画。
18. **ピンチ拡大ルーペ（ミニマップ付き）＆ 黒帯オートクロップ**: 最大10倍円形ルーペ、右下ミニマップ表示、上下黒帯の輝度自動検出・シームレスズーム。
19. **リアルタイム手ぶれ補正 ＆ モーションアダプティブ・デインターレース**: 16×16マクロブロック・オプティカルフロー逆補正、櫛形ノイズ検出適応型デインターレース。
20. **フィルター適用済み高画質PNGスナップショット保存**: リアルタイムシェーダー適用後バッファのPNG可逆圧縮保存。

### Module C: 軽量高速スキャン ＆ インタラクティブ波形シーク (`UltimateWaveformEngine`)
21. **軽量キャッシュ式 音声波形シークバー**: `AVAssetReader` 並列スキャンによるRMS/Peakバイナリキャッシュ化。60fpsスクラブ追従。
22. **無音区間オートスキップ**: -45dB以下・0.4秒以上の無音区間を事前検知し、2.5倍速自動加速スキップ。
23. **盛り上がり自動ヒートマップ**: 短期エネルギースペクトルフラックスからハイライト度を算出し、波形に寒色→暖色グラデーションをマッピング。
24. **波形ドラッグABリピート ＆ 区間メモ**: 波形上2点直感ドラッグによるループ設定、触覚クリック、タイトル・メモ付与。
25. **字幕・区間メモのSQLite（FTS5）全文検索**: C言語 SQLite3 FTS5仮想テーブル（`unicode61`）による字幕・区間メモの高速全文検索。

### Module D: 二カ国語字幕 ＆ 学習・練習エンジン (`UltimateSubtitleAndStudyEngine`)
26. **二カ国語SRT同時表示 ＆ 単語タップ内蔵辞書**: 二分探索 $O(\log N)$ タイムコード照合、単語タップ `UIReferenceLibraryViewController` 辞書表示。
27. **画面内テキストOCR翻訳・コピー**: Vision `.accurate` による一時停止フレーム文字認識、バウンディングボックス選択。
28. **シャドーイング＆発音比較レコーダー**: フレーズ終了時自動ポーズ＆録音、「お手本音声 → 自分の声」自動交互再生比較。
29. **反復練習スピードトレーナー**: ABリピート1ループごとの自動速度ステップアップ（`0.70x → 1.00x`）。

### Module E: システム連携 ＆ 書き出しエンジン (`UltimateSystemIntegration`)
30. **Live Activities ＆ Dynamic Island フル操作**: ロック画面・ダイナミックアイランドでのミニ波形表示、`AppIntents` バックグラウンド操作。
31. **NFCタグ物理オートメーション**: `CoreNFC` NDEFタグ読取・書込によるDSP・タイマーワンタッチ適用。
32. **音声のみ超省電力モード ＆ カスタムPiP**: Metalパイプライン完全サスペンド（VRAM解放）、字幕焼き込みPiPレイヤー。
33. **ローカルWi-Fi ブラウザリモコン ＆ 2台同期視聴**: `Network.framework` 組み込み HTTP + RFC 6455 WebSocket サーバー、ミリ秒クロック同期。
34. **非破壊トリミング ＆ DSP/フィルター焼き込み書き出し**: `AVAssetExportPresetPassthrough` 無劣化カット保存、DSP/シェーダー焼き込み出力。

### Module F: 操作性 ＆ プライバシー管理 (`UltimateUXAndVault`)
35. **変態ジェスチャー＆ジョグダイヤル**: 画面長押し2.0x倍速、1コマ精密回転ジョグダイヤル、2本指輝度/音量スワイプ。
36. **フォルダ別設定自動記憶**: ディレクトリハッシュ単位のSQLite自動永続化ストア（速度・DSP・シェーダー自動復元）。
37. **電卓偽装シークレットフォルダ**: 完全動作電卓UI、`7749=` 数式パスコードトリガー、AES-GCM暗号化保管庫、バックグラウンド即時自動ロック。
38. **安眠フェードアウトタイマー**: 終了60秒前対数音量フェード ＆ 20kHz→250Hzローパス動的絞り込み、自動画面ロック誘導。

---

## 📦 GitHub Actions による IPA 自動ビルド

本リポジトリには、GitHub Actions 経由でワンクリックで署名なし・サイドロード可能な `.ipa` を自動ビルド・パッケージングするワークフローが同梱されています：
- **ワークフロー定義**: [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml)
- **生成されるIPA**: `VLC-Ultimate-Hikaproj.ipa`
- **インストール対応ツール**: AltStore, TrollStore, Sideloadly, Scarlet 等でそのまま署名・実機転送可能です。

---

This is the official mirror repository of VLC for iOS and tvOS application.

_You can find the official repository [here](https://code.videolan.org/videolan/vlc-ios/)._

It's currently written in Objective-C / Swift and uses [VLCKit](https://code.videolan.org/videolan/VLCKit), a libvlc wrapper.

- [Requirements](#requirements)
- [Building](#building)
  - [VLC-iOS](#vlc-ios)
  - [Custom VLCKit](#custom-vlckit)
  - [Beginner's Guide](#beginners-guide)
- [Contribute](#contribute)
  - [Pull request](#pull-request)
  - [Commit](#commit)
  - [Gitlab issues](#gitlab-issues)
- [Communication](#communication)
  - [Forum](#forum)
  - [Issues](#issues)
- [Code of Conduct](#code-of-conduct)
- [License](#license)
- [More](#more)

## Requirements
* Xcode 11.0+
* macOS 10.12+
* Cocoapods 1.4+

## Building

### VLC-iOS

1. Clone VLC-iOS:

    `git clone https://code.videolan.org/videolan/vlc-ios.git`

2. Run the command `[sudo] gem install cocoapods` (and then `[sudo] arch -x86_64 gem install ffi` on Apple Silicon devices).    
3. Run `pod install` (or `arch -x86_64 pod install` on Apple Silicon devices).
4. Open `VLC.xcworkspace`.
5. Hit "Build and Run".


### Custom VLCKit

Mostly for debugging or advanced users, you might want to have a custom local VLCKit build.

1. Clone VLCKit:

    `git clone https://code.videolan.org/videolan/VLCKit.git`


2. Inside the VLCKit folder, run the following command:

    `./compileAndBuildVLCKit.sh -a ${MYARCH}`

    MYARCH can be `x86_64` or `aarch64`.

    Add `-d` for a debug build (to have valid stack straces and asserts).

    Add `-n` if you want to use you own VLC repository for VLCKit (See [VLCKit README.md](https://code.videolan.org/videolan/VLCKit/blob/master/README.md)).

3. Replace the VLCKit.framework with the one you just built.

    Inside your vlc-ios folder, after a `pod update`, do:

    `cd Pods/VLCKit`

    `rm -rf VLCKit.xcframework`

    `ln -s ${VLCKit}/build/VLCKit.xcframework`

4. Hit "Build and Run".

### Beginner's Guide

Can't get your project to build or run? Head over to the [beginner's guide](https://code.videolan.org/videolan/vlc-ios/wikis/Beginner-Guide) for help on common issues beginners tend to run into.

If you can't find your problem on the guide, please feel free to [submit an issue](https://code.videolan.org/videolan/vlc-ios/issues).

## Contribute

### Pull request

Pull requests are more than welcome! If you do submit one, please make sure to use a descriptive title and description.

### Commit

We try to follow a simple set of rules, outlined by this [guide](https://chris.beams.io/posts/git-commit/).

Additionally, commit messages should have all the information needed to understand the commit easily as the following:

```
    Subject: Brief description

    Description in detail if needed.

    ticket related action
```

For example:

```
    UPnP: Remove iOS 7 compatibility code

    Closes #166
```

Further rules can be found on this [Coding Style](./Documentation/CodingStyle.md) guide.

### Gitlab issues

You can look through issues we currently have on the [VideoLAN GitLab](https://code.videolan.org/videolan/vlc-ios/issues).

A [beginner friendly](https://code.videolan.org/videolan/vlc-ios/issues?label_name%5B%5D=Beginner+friendly) tag is available if you don't know where to start.

## Communication

### Forum

If you have any question or if you're not sure it's actually an issue, please visit our [forum](https://forum.videolan.org/).

### Issues

You have encountered an issue and wish to report it to the VLC dev team?

You can create one on our [GitLab](https://code.videolan.org/videolan/vlc-ios/issues).

Before creating an issue or ticket, please double check for duplicates!

Two templates are provided helping you report an issue and request a feature.

Each section of the template should contain at least one meaningful sentence in order to guarantee a proper understanding of the ticket.

## Code of Conduct

Please read and follow the [VideoLAN CoC](https://wiki.videolan.org/Code_of_Conduct/).

## License

VLC-iOS is under the GPLv2 (or later) and the MPLv2 license.

See [COPYING](./COPYING) for more license info.

## More

For everything else, check our [wiki](https://wiki.videolan.org/) or our [support page](http://www.videolan.org/support/).

We're happy to help!
