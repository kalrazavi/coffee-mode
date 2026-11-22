import AppKit
import SwiftUI
import ServiceManagement
import IOKit.pwr_mgt

// ---------- The little coffee cup (drawn in code, so it stays sharp at any size) ----------
enum CupArt {
    static let frames = 8
    // Design space is 28 x 22 points. The cup faces right.
    static func draw(phase: CGFloat, turbo: Bool, size: CGSize, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: size.width / 28, y: size.height / 22)
        color.setFill(); color.setStroke()
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let swing = sin(phase * 2 * .pi)
        let amp: CGFloat = turbo ? 0.95 : 0.42
        let bounce = abs(swing) * (turbo ? 1.1 : 0.35)

        if turbo {   // speed lines behind the cup
            ctx.setLineWidth(1.1)
            let ys: [CGFloat] = [15.2, 11.4, 7.6]
            for (i, y) in ys.enumerated() {
                let shift = CGFloat((Int(phase * 8) + i * 3) % 4) * 0.7
                ctx.move(to: CGPoint(x: 0.8 + shift, y: y))
                ctx.addLine(to: CGPoint(x: 3.2 + shift + (i == 1 ? 1.2 : 0), y: y))
                ctx.strokePath()
            }
        }

        ctx.translateBy(x: turbo ? 16 : 14.5, y: (turbo ? 6.3 : 5.4) + bounce)
        if turbo { ctx.rotate(by: -0.20) }

        // legs
        ctx.setLineWidth(1.5)
        let legLen: CGFloat = turbo ? 5.0 : 4.4
        let hips: [(CGFloat, CGFloat)] = [(-2.0, 1), (2.0, -1)]
        for (hx, sign) in hips {
            let a = sign * swing * amp
            let foot = CGPoint(x: hx + sin(a) * legLen, y: -cos(a) * legLen)
            ctx.move(to: CGPoint(x: hx, y: 0.3)); ctx.addLine(to: foot)
            ctx.addLine(to: CGPoint(x: foot.x + 1.7, y: foot.y + (turbo ? 0.5 * sign * swing : 0)))
            ctx.strokePath()
        }

        // cup body
        let body = CGMutablePath()
        body.move(to: CGPoint(x: -5.6, y: 8.6))
        body.addLine(to: CGPoint(x: 5.6, y: 8.6))
        body.addLine(to: CGPoint(x: 4.6, y: 1.6))
        body.addQuadCurve(to: CGPoint(x: 3.0, y: 0), control: CGPoint(x: 4.4, y: 0))
        body.addLine(to: CGPoint(x: -3.0, y: 0))
        body.addQuadCurve(to: CGPoint(x: -4.6, y: 1.6), control: CGPoint(x: -4.4, y: 0))
        body.closeSubpath()
        ctx.addPath(body); ctx.fillPath()

        // handle (at the back)
        ctx.setLineWidth(1.4)
        ctx.move(to: CGPoint(x: -5.2, y: 6.9))
        ctx.addCurve(to: CGPoint(x: -4.8, y: 2.6), control1: CGPoint(x: -9.2, y: 7.2), control2: CGPoint(x: -8.6, y: 2.2))
        ctx.strokePath()

        // eyes (cut out)
        ctx.setBlendMode(.clear)
        let eyeH: CGFloat = turbo ? 1.0 : 1.7
        ctx.fillEllipse(in: CGRect(x: 0.4, y: 5.4 - eyeH / 2, width: 1.5, height: eyeH))
        ctx.fillEllipse(in: CGRect(x: 3.0, y: 5.4 - eyeH / 2, width: 1.5, height: eyeH))
        ctx.setBlendMode(.normal)

        // steam
        ctx.setLineWidth(1.1)
        let drift: CGFloat = turbo ? -4.2 : swing * 0.7
        for sx in [CGFloat(-1.8), 2.0] {
            ctx.move(to: CGPoint(x: sx, y: 10.0))
            ctx.addCurve(to: CGPoint(x: sx + drift, y: 13.3),
                         control1: CGPoint(x: sx + 1.3 + drift * 0.2, y: 11.0),
                         control2: CGPoint(x: sx - 1.3 + drift * 0.8, y: 12.2))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    static func image(frame: Int, turbo: Bool, size: CGSize, color: NSColor, template: Bool) -> NSImage {
        let img = NSImage(size: size, flipped: false) { _ in
            draw(phase: CGFloat(frame) / CGFloat(frames), turbo: turbo, size: size, color: color)
            return true
        }
        img.isTemplate = template
        return img
    }
}

// ---------- Keeping the Mac awake ----------
// Nothing in System Settings is changed. Coffee Mode only holds "stay awake" requests with macOS;
// switching it off (or quitting, or a crash) drops them and the Mac behaves exactly as before.
final class Awake {
    private var ids: [IOPMAssertionID] = []
    private var activity = IOPMAssertionID(0)
    private var poke: Timer?
    func on() {
        guard ids.isEmpty else { return }
        for type in ["PreventUserIdleDisplaySleep", "PreventUserIdleSystemSleep", "PreventSystemSleep", "PreventDiskIdle"] {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "Coffee Mode: keep everything awake" as CFString, &id) == kIOReturnSuccess { ids.append(id) }
        }
        // also tell macOS "someone is here" every 30 s so the screen never dims and the screensaver never starts
        let tick = { [weak self] in
            guard let self = self else { return }
            IOPMAssertionDeclareUserActivity("Coffee Mode" as CFString, kIOPMUserActiveLocal, &self.activity)
        }
        tick()
        poke = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in tick() }
    }
    func off() {
        poke?.invalidate(); poke = nil
        ids.forEach { IOPMAssertionRelease($0) }; ids = []
        if activity != 0 { IOPMAssertionRelease(activity); activity = 0 }
    }
    var held: Int { ids.count }
}

// ---------- State ----------
final class Model: ObservableObject {
    @Published var isOn = false
    @Published var frame = 0
    @Published var since: Date? = nil
    @Published var loginItem = false
    let awake = Awake()
    var onChange: (() -> Void)?
    init() { loginItem = (SMAppService.mainApp.status == .enabled) }
    func set(_ on: Bool) {
        guard on != isOn else { return }
        if on { awake.on(); since = Date() } else { awake.off(); since = nil }
        isOn = on
        onChange?()
    }
    func setLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { NSLog("login item: \(error)") }
        loginItem = (SMAppService.mainApp.status == .enabled)
    }
    var awakeText: String {
        guard let s = since else { return "" }
        let m = Int(Date().timeIntervalSince(s)) / 60
        if m < 1 { return "Just switched on" }
        if m < 60 { return "Awake for \(m) min" }
        return "Awake for \(m / 60) h \(m % 60) min"
    }
}

// ---------- The card ----------
let amber = Color(red: 1.0, green: 0.69, blue: 0.25)

struct BigToggle: View {
    @Binding var on: Bool
    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? amber : Color.white.opacity(0.14))
            Text(on ? "TURBO" : "NORMAL")
                .font(.system(size: 11, weight: .heavy, design: .rounded)).kerning(1.2)
                .foregroundColor(on ? Color.black.opacity(0.75) : Color.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: on ? .leading : .trailing)
                .padding(.horizontal, 18)
            Circle().fill(Color.white).shadow(color: .black.opacity(0.35), radius: 3, y: 1).padding(4)
        }
        .frame(width: 132, height: 44)
        .contentShape(Capsule())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { on.toggle() } }
        .accessibilityLabel("Coffee Mode").accessibilityValue(on ? "on" : "off")
    }
}

struct Card: View {
    @ObservedObject var m: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: CupArt.image(frame: m.frame, turbo: m.isOn, size: CGSize(width: 92, height: 72),
                                            color: m.isOn ? NSColor(amber) : NSColor(white: 0.60, alpha: 1), template: false))
                    .frame(width: 92, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coffee Mode").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text(m.isOn ? "Fully caffeinated. Nothing sleeps." : "Decaf. Your Mac rests as usual.")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                BigToggle(on: Binding(get: { m.isOn }, set: { m.set($0) }))
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(m.isOn ? m.awakeText : "Screen and sleep: normal")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(m.isOn ? amber : .white.opacity(0.5))
                    Text(m.isOn ? "No sleep, no dimming" : "Switch on before a long task")
                        .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.42))
                }
            }
            Divider().background(Color.white.opacity(0.12))
            HStack {
                HStack(spacing: 7) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4).fill(m.loginItem ? amber : Color.white.opacity(0.12)).frame(width: 15, height: 15)
                        if m.loginItem { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.black.opacity(0.75)) }
                    }
                    Text("Open at login").font(.system(size: 11.5)).foregroundColor(.white.opacity(0.7))
                }
                .contentShape(Rectangle())
                .onTapGesture { m.setLogin(!m.loginItem) }
                Spacer()
                Button("Quit") { m.set(false); NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(18)
        .frame(width: 330)
        .background(LinearGradient(colors: [Color(red: 0.13, green: 0.11, blue: 0.10), Color(red: 0.08, green: 0.07, blue: 0.07)],
                                   startPoint: .top, endPoint: .bottom))
    }
}

// ---------- Menu bar ----------
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = Model()
    var item: NSStatusItem!
    let popover = NSPopover()
    var timer: Timer?
    var walk: [NSImage] = [], run: [NSImage] = []
    var sig: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ n: Notification) {
        let size = CGSize(width: 26, height: 20.4)
        walk = (0..<CupArt.frames).map { CupArt.image(frame: $0, turbo: false, size: size, color: .black, template: true) }
        run = (0..<CupArt.frames).map { CupArt.image(frame: $0, turbo: true, size: size, color: .black, template: true) }
        item = NSStatusBar.system.statusItem(withLength: 30)
        item.button?.image = walk[0]
        item.button?.target = self; item.button?.action = #selector(toggle(_:))
        item.button?.toolTip = "Coffee Mode"
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: Card(m: model))
        model.onChange = { [weak self] in self?.restartTimer() }
        restartTimer()
        // "kill -USR1 <pid>" flips the switch, the same way a click does (used for testing and by scripts)
        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in guard let s = self else { return }; s.model.set(!s.model.isOn) }
        src.resume(); sig = src
    }
    func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: model.isOn ? 0.07 : 0.30, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            s.model.frame = (s.model.frame + 1) % CupArt.frames
            s.item.button?.image = (s.model.isOn ? s.run : s.walk)[s.model.frame]
            s.item.button?.toolTip = s.model.isOn ? "Coffee Mode: on. \(s.model.awakeText)" : "Coffee Mode: off"
        }
        RunLoop.main.add(t, forMode: .common); timer = t
    }
    @objc func toggle(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender); return }
        guard let b = item.button else { return }
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func applicationWillTerminate(_ n: Notification) { model.awake.off() }
}

// ---------- Preview pictures (used only while building, to check the look) ----------
func writePNG(_ img: NSImage, _ path: String, scale: CGFloat) {
    let w = Int(img.size.width * scale), h = Int(img.size.height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func sheet(turbo: Bool, dark: Bool) -> NSImage {
    let fs = CGSize(width: 26, height: 20.4)
    return NSImage(size: CGSize(width: fs.width * 8 + 36, height: fs.height + 8), flipped: false) { r in
        (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill(); r.fill()
        for f in 0..<8 {
            let im = CupArt.image(frame: f, turbo: turbo, size: fs, color: dark ? .white : .black, template: false)
            im.draw(at: CGPoint(x: 4 + CGFloat(f) * (fs.width + 4), y: 4), from: .zero, operation: .sourceOver, fraction: 1)
        }
        return true
    }
}
func appIcon() -> NSImage {
    NSImage(size: CGSize(width: 1024, height: 1024), flipped: false) { r in
        let p = NSBezierPath(roundedRect: r.insetBy(dx: 100, dy: 100), xRadius: 185, yRadius: 185)
        NSGradient(colors: [NSColor(red: 0.20, green: 0.16, blue: 0.13, alpha: 1), NSColor(red: 0.09, green: 0.08, blue: 0.07, alpha: 1)])!.draw(in: p, angle: -90)
        let s = CGSize(width: 640, height: 503)
        CupArt.image(frame: 2, turbo: true, size: s, color: NSColor(red: 1.0, green: 0.69, blue: 0.25, alpha: 1), template: false)
            .draw(at: CGPoint(x: 192, y: 265), from: .zero, operation: .sourceOver, fraction: 1)
        return true
    }
}

let args = CommandLine.arguments
if args.count > 2, args[1] == "--render" {
    let dir = args[2]
    writePNG(sheet(turbo: false, dark: true), dir + "/walk_dark.png", scale: 6)
    writePNG(sheet(turbo: true, dark: true), dir + "/run_dark.png", scale: 6)
    writePNG(sheet(turbo: true, dark: false), dir + "/run_light.png", scale: 6)
    writePNG(appIcon(), dir + "/icon_1024.png", scale: 1)
    MainActor.assumeIsolated {
        for on in [false, true] {
            let m = Model(); m.isOn = on; m.frame = 2; if on { m.since = Date().addingTimeInterval(-47 * 60) }
            let r = ImageRenderer(content: Card(m: m).environment(\.colorScheme, .dark)); r.scale = 2
            if let im = r.nsImage { writePNG(im, dir + (on ? "/card_on.png" : "/card_off.png"), scale: 2) }
        }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
