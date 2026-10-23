import Foundation
import WebKit
import AppKit

// Usage: swift generate-background.swift [version] [output_dir]
let width: CGFloat = 660
let height: CGFloat = 460

let version = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "1.1.1"
let outputDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/DMG"

// Locate SVG logo
let possiblePaths = [
    "docs/brand/clipkeep-horizontal-color-on-dark.svg",
    "../docs/brand/clipkeep-horizontal-color-on-dark.svg",
    "../../docs/brand/clipkeep-horizontal-color-on-dark.svg"
]
var logoSvg = ""
for path in possiblePaths {
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        logoSvg = content
        break
    }
}

let html = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    width: \(Int(width))px;
    height: \(Int(height))px;
    overflow: hidden;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", sans-serif;
    background-color: #161413;
    background-image:
      radial-gradient(ellipse 65% 45% at 50% 0%, rgba(212, 90, 18, 0.30) 0%, rgba(22, 20, 19, 0) 70%),
      radial-gradient(circle at 160px 190px, rgba(212, 90, 18, 0.20) 0%, rgba(22, 20, 19, 0) 60%),
      radial-gradient(circle at 500px 190px, rgba(55, 135, 255, 0.09) 0%, rgba(22, 20, 19, 0) 60%),
      linear-gradient(180deg, #221F1C 0%, #141211 100%);
    position: relative;
    user-select: none;
    -webkit-font-smoothing: antialiased;
  }

  /* Refined dot grid */
  .grid-pattern {
    position: absolute;
    inset: 0;
    background-image: radial-gradient(rgba(255, 255, 255, 0.065) 1px, transparent 1px);
    background-size: 20px 20px;
    mask-image: radial-gradient(ellipse 85% 75% at 50% 45%, black 35%, transparent 85%);
    -webkit-mask-image: radial-gradient(ellipse 85% 75% at 50% 45%, black 35%, transparent 85%);
    pointer-events: none;
  }

  /* Header */
  .header {
    position: absolute;
    top: 25px;
    left: 0;
    right: 0;
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .logo-row {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
  }

  .logo-wrap {
    height: 42px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .logo-wrap svg {
    height: 38px;
    width: auto;
    filter: drop-shadow(0 2px 10px rgba(0, 0, 0, 0.6));
  }

  .version-tag {
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid rgba(255, 255, 255, 0.12);
    color: rgba(255, 255, 255, 0.65);
    font-size: 11px;
    font-weight: 500;
    padding: 2px 7px;
    border-radius: 8px;
    letter-spacing: 0.3px;
    margin-left: 2px;
  }

  .subtitle {
    margin-top: 5px;
    font-size: 12px;
    color: rgba(255, 255, 255, 0.55);
    letter-spacing: 0.25px;
    font-weight: 400;
  }

  /* Drop target pedestals */
  .pedestal {
    position: absolute;
    width: 114px;
    height: 114px;
    border-radius: 26px;
    top: 133px; /* centered around y=190: 190 - 57 = 133 */
  }

  .pedestal-left {
    left: 103px; /* centered around x=160: 160 - 57 = 103 */
    background: linear-gradient(135deg, rgba(212, 90, 18, 0.12) 0%, rgba(212, 90, 18, 0.02) 100%);
    border: 1.5px solid rgba(212, 90, 18, 0.4);
    box-shadow: 0 0 32px rgba(212, 90, 18, 0.24), inset 0 1px 1px rgba(255, 255, 255, 0.15);
  }

  .pedestal-right {
    left: 443px; /* centered around x=500: 500 - 57 = 443 */
    background: linear-gradient(135deg, rgba(255, 255, 255, 0.04) 0%, rgba(255, 255, 255, 0.01) 100%);
    border: 1.5px dashed rgba(255, 255, 255, 0.25);
    box-shadow: 0 0 32px rgba(0, 0, 0, 0.4), inset 0 1px 1px rgba(255, 255, 255, 0.1);
  }

  /* Center drag indicator */
  .drag-arrow-container {
    position: absolute;
    left: 225px;
    top: 158px;
    width: 210px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
  }

  .drag-badge {
    background: linear-gradient(135deg, rgba(212, 90, 18, 0.25) 0%, rgba(212, 90, 18, 0.1) 100%);
    border: 1px solid rgba(212, 90, 18, 0.5);
    color: #FFA366;
    font-size: 9.5px;
    font-weight: 700;
    letter-spacing: 1.2px;
    text-transform: uppercase;
    padding: 3px 12px;
    border-radius: 20px;
    margin-bottom: 9px;
    box-shadow: 0 2px 10px rgba(212, 90, 18, 0.25);
    display: flex;
    align-items: center;
    gap: 5px;
  }

  .drag-badge svg {
    width: 10px;
    height: 10px;
  }

  .arrow-svg {
    width: 170px;
    height: 24px;
    filter: drop-shadow(0 2px 8px rgba(212, 90, 18, 0.6));
  }

  /* Bottom Help Card - slightly taller for comfortable label padding */
  .help-card {
    position: absolute;
    left: 40px;
    right: 40px;
    bottom: 16px;
    height: 110px;
    border-radius: 16px;
    background: linear-gradient(135deg, rgba(35, 31, 28, 0.88) 0%, rgba(23, 20, 18, 0.94) 100%);
    border: 1px solid rgba(255, 255, 255, 0.08);
    box-shadow: 0 10px 28px rgba(0, 0, 0, 0.45), inset 0 1px 0 rgba(255, 255, 255, 0.08);
    display: flex;
    align-items: center;
    padding: 0 16px 0 22px;
  }

  .help-card::before {
    content: "";
    position: absolute;
    left: 0;
    top: 14px;
    bottom: 14px;
    width: 3.5px;
    background: linear-gradient(180deg, #FF8833 0%, #D45A12 100%);
    border-radius: 0 3px 3px 0;
    box-shadow: 0 0 12px rgba(212, 90, 18, 0.65);
  }

  .help-text {
    flex: 1;
    padding-right: 120px;
  }

  .help-title {
    font-size: 12.5px;
    font-weight: 600;
    color: #FFFFFF;
    display: flex;
    align-items: center;
    gap: 7px;
    margin-bottom: 5px;
  }

  .help-title-badge {
    background: rgba(212, 90, 18, 0.22);
    border: 1px solid rgba(212, 90, 18, 0.45);
    color: #FFA366;
    font-size: 9px;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 4px;
    letter-spacing: 0.3px;
  }

  .help-desc {
    font-size: 11px;
    line-height: 1.48;
    color: rgba(255, 255, 255, 0.65);
  }

  .help-desc strong {
    color: rgba(255, 255, 255, 0.95);
    font-weight: 600;
  }

  .help-desc em {
    color: #FFB380;
    font-style: normal;
  }

  /* Readme slot indicator - aligned precisely with icon at {500, 348} */
  .readme-slot {
    position: absolute;
    right: 82px;
    top: 8px;
    width: 76px;
    height: 72px;
    border-radius: 12px;
    border: 1.5px dashed rgba(255, 255, 255, 0.14);
    background: rgba(255, 255, 255, 0.015);
    display: flex;
    align-items: center;
    justify-content: center;
    pointer-events: none;
  }

  .readme-slot svg {
    width: 22px;
    height: 22px;
    opacity: 0.16;
    fill: none;
    stroke: #FFFFFF;
    stroke-width: 1.5;
  }
</style>
</head>
<body>
  <div class="grid-pattern"></div>

  <div class="header">
    <div class="logo-row">
      <div class="logo-wrap">
        \(logoSvg)
      </div>
      <div class="version-tag">v\(version)</div>
    </div>
    <div class="subtitle">Minimal menu bar clipboard manager for macOS</div>
  </div>

  <!-- Pedestals behind the drag and target icons -->
  <div class="pedestal pedestal-left"></div>
  <div class="pedestal pedestal-right"></div>

  <!-- Directional arrow & drag badge -->
  <div class="drag-arrow-container">
    <div class="drag-badge">
      <svg viewBox="0 0 24 24"><path d="M5 12h14M13 6l6 6-6 6" stroke="#FFA366" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg>
      Drag to Install
    </div>
    <svg class="arrow-svg" viewBox="0 0 170 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="arrowGrad" x1="0" y1="12" x2="170" y2="12" gradientUnits="userSpaceOnUse">
          <stop offset="0%" stop-color="#D45A12" stop-opacity="0.25"/>
          <stop offset="35%" stop-color="#D45A12"/>
          <stop offset="85%" stop-color="#FF7A29"/>
          <stop offset="100%" stop-color="#FFA366"/>
        </linearGradient>
      </defs>
      <path d="M 8 12 L 142 12" stroke="url(#arrowGrad)" stroke-width="3" stroke-linecap="round" stroke-dasharray="6 5"/>
      <path d="M 126 6 L 136 12 L 126 18" stroke="#FF7A29" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" opacity="0.5"/>
      <path d="M 138 5 L 150 12 L 138 19" stroke="#FFA366" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  </div>

  <!-- Bottom Help Card -->
  <div class="help-card">
    <div class="help-text">
      <div class="help-title">
        <span>First time opening ClipKeep?</span>
        <span class="help-title-badge">macOS Gatekeeper</span>
      </div>
      <div class="help-desc">
        If macOS says it <em>"could not verify"</em> the app, click <strong>Done</strong>, then open<br>
        <strong>System Settings &gt; Privacy &amp; Security</strong> and click <strong>Open Anyway</strong>.<br>
        Or double-click the <strong>Read me</strong> guide on the right for Terminal install.
      </div>
    </div>
    <div class="readme-slot">
      <svg viewBox="0 0 24 24"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
    </div>
  </div>
</body>
</html>
"""

let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height))
webView.loadHTMLString(html, baseURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

let semaphore = DispatchSemaphore(value: 0)
var snapshotImage: NSImage?

class NavDelegate: NSObject, WKNavigationDelegate {
    let sema: DispatchSemaphore
    init(sema: DispatchSemaphore) { self.sema = sema }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let config = WKSnapshotConfiguration()
            webView.takeSnapshot(with: config) { image, error in
                snapshotImage = image
                self.sema.signal()
            }
        }
    }
}

let delegate = NavDelegate(sema: semaphore)
webView.navigationDelegate = delegate

let start = Date()
while snapshotImage == nil && Date().timeIntervalSince(start) < 4.0 {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
}

guard let image = snapshotImage else {
    print("Failed to capture snapshot")
    exit(1)
}

func savePNG(image: NSImage, scale: CGFloat, path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width * scale),
        pixelsHigh: Int(height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
               from: NSRect.zero,
               operation: .copy,
               fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let png1x = "\(outputDir)/background.png"
let png2x = "\(outputDir)/background@2x.png"
let tiffPath = "\(outputDir)/background.tiff"

savePNG(image: image, scale: 1.0, path: png1x)
savePNG(image: image, scale: 2.0, path: png2x)

let task = Process()
task.launchPath = "/usr/bin/tiffutil"
task.arguments = ["-cathidpicheck", png1x, png2x, "-out", tiffPath]
task.launch()
task.waitUntilExit()

print("Generated \(tiffPath) successfully!")
