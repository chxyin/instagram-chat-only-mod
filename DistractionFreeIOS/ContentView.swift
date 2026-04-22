import SwiftUI
import WebKit
import Combine

struct ContentView: View {
    @AppStorage("zoomLevel") private var zoomLevel: Int = 100
    @AppStorage("offsetX") private var offsetX: Double = 0.0
    @AppStorage("offsetY") private var offsetY: Double = 0.0
    @AppStorage("mediaAllowed") private var mediaAllowed: Bool = false
   
    @State private var screenTimeSeconds: Int = 0
    @State private var webView: WKWebView? = nil
    @State private var menuExpanded = false
    @State private var currentDragOffset: CGSize = .zero
   
    // Timer for screen time tracking
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
   
    // Calculate today's key for AppStorage based tracking
    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "screenTime_" + formatter.string(from: Date())
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.ignoresSafeArea()
            
            // Instagram WKWebView Wrapper
            WebViewWrapper(
                zoomLevel: $zoomLevel,
                mediaAllowed: $mediaAllowed,
                webViewRef: $webView
            )
            .onAppear {
                screenTimeSeconds = UserDefaults.standard.integer(forKey: todayKey)
            }
            .onReceive(timer) { _ in
                screenTimeSeconds += 1
                if screenTimeSeconds % 10 == 0 {
                    UserDefaults.standard.set(screenTimeSeconds, forKey: todayKey)
                }
            }
           
            // Screen Time / Menu FAB
            Menu {
                Button(action: {
                    mediaAllowed.toggle()
                    webView?.evaluateJavaScript("window.toggleMediaAllowed(\(mediaAllowed));", completionHandler: nil)
                }) {
                    Text(mediaAllowed ? "Media: ON" : "Media: OFF")
                }
               
                Button(action: {
                    zoomLevel += 10
                    if zoomLevel > 180 { zoomLevel = 60 }
                    webView?.evaluateJavaScript("document.body.style.zoom = '\(zoomLevel)%';", completionHandler: nil)
                }) {
                    Text("Zoom View: \(zoomLevel)%")
                }
            } label: {
                Text("⏳ \(formattedScreenTime)  ▼")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(16)
            }
            .offset(
                x: max(-21, min(CGFloat(offsetX) + currentDragOffset.width, UIScreen.main.bounds.width - 130)),
                y: max(-UIScreen.main.bounds.height + 100, min(CGFloat(offsetY) + currentDragOffset.height, 21))
            )
            .padding(24)
            // Long Press and Drag implementation
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0.0, coordinateSpace: .local))
                    .onChanged { value in
                        switch value {
                        case .second(true, let drag):
                            if let drag = drag {
                                currentDragOffset = drag.translation
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        switch value {
                        case .second(true, let drag):
                            if let drag = drag {
                                let newX = CGFloat(offsetX) + drag.translation.width
                                let newY = CGFloat(offsetY) + drag.translation.height
                                
                                offsetX = Double(max(-21, min(newX, UIScreen.main.bounds.width - 130)))
                                offsetY = Double(max(-UIScreen.main.bounds.height + 100, min(newY, 21)))
                                currentDragOffset = .zero
                            }
                        default:
                            break
                        }
                    }
            )
        }
    }
   
    private var formattedScreenTime: String {
        let hours = screenTimeSeconds / 3600
        let minutes = (screenTimeSeconds % 3600) / 60
        let seconds = screenTimeSeconds % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm %d%ds", minutes, seconds / 10, seconds % 10)
        }
    }
}

struct WebViewWrapper: UIViewRepresentable {
    @Binding var zoomLevel: Int
    @Binding var mediaAllowed: Bool
    @Binding var webViewRef: WKWebView?
   
    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
       
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        
        DispatchQueue.main.async {
            webViewRef = webView
        }
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
       
        if let url = URL(string: "https://www.instagram.com/") {
            webView.load(URLRequest(url: url))
        }
       
        return webView
    }
   
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // UI updates can go here if state changes outside JS
    }
   
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
   
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewWrapper
       
        init(_ parent: WebViewWrapper) {
            self.parent = parent
        }
       
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let jsScript = """
                javascript:(function() {
                    if (window.distractionFreeInitialized) return;
                    window.distractionFreeInitialized = true;
                    window.mediaAllowed = \(parent.mediaAllowed);

                    // 1. INSTANT CSS INJECTION
                    const style = document.createElement('style');
                    style.innerHTML = `
                        body { background-color: black !important; margin: 0 !important; padding: 0 !important; }
                        
                        /* Hide only Reels tab and link */
                        a[href^="/reels/"] {
                            display: none !important;
                        }

                        /* Make reply button in DMs massively larger */
                        svg[aria-label="Reply" i] {
                            transform: scale(2.0) !important;
                        }
                        
                        div:has(> svg[aria-label="Reply" i]),
                        [aria-label="Reply" i] {
                            padding: 20px !important;
                            margin: -10px !important;
                        }
                    `;
                    document.head.appendChild(style);

                    // 2. NATIVE TOGGLE FUNCTION
                    window.toggleMediaAllowed = function(allowed) {
                        window.mediaAllowed = allowed;
                        if (allowed) {
                            document.querySelectorAll('video').forEach(el => {
                                if (el.dataset.blockedSrc) {
                                    el.src = el.dataset.blockedSrc;
                                    if (el.tagName === 'VIDEO') el.play();
                                }
                            });
                        }
                    };

                    // 3. LOGIC LOOP OVERRIDE
                    setInterval(() => {
                        try {
                            const path = window.location.pathname;

                            // If they try to navigate directly to reels, go back
                            if (path.startsWith('/reels/')) {
                                window.history.back();
                                return;
                            }

                            // Media Block
                            if (!window.mediaAllowed) {
                                document.querySelectorAll('video').forEach(video => {
                                    if (video.src && video.src !== '') {
                                        video.dataset.blockedSrc = video.src;
                                        video.removeAttribute('src');
                                        video.load();
                                    }
                                });
                            }

                            // Extra aggressive attempt to hide Reels inside the main feed
                            const textNodes = document.querySelectorAll('span, div, h2, a');
                            for (let el of textNodes) {
                                if (el.children.length === 0 && el.textContent) {
                                    const txt = el.textContent.trim().toLowerCase();

                                    // Hide "Use the App" banners
                                    if (txt.includes('instagram app') || txt.includes('use the app') || txt === 'open app') {
                                        let p = el;
                                        for (let i = 0; i < 6; i++) {
                                            if (!p || p.tagName === 'BODY' || p.id === 'react-root') break;
                                            if (p.offsetHeight > 0 && p.offsetHeight <= 120) {
                                                p.style.setProperty('display', 'none', 'important');
                                            }
                                            p = p.parentElement;
                                        }
                                    }
                                }
                            }

                            // Specifically look for Reels SVG to hide suggested reels in feed
                            const reelIcons = document.querySelectorAll('svg[aria-label="Reels" i]');
                            reelIcons.forEach(icon => {
                                let p = icon;
                                for (let i = 0; i < 8; i++) {
                                    if (!p || p.tagName === 'BODY' || p.tagName === 'ARTICLE') break;
                                    p = p.parentElement;
                                }
                                if (p && p.tagName === 'ARTICLE') {
                                    p.style.setProperty('display', 'none', 'important');
                                }
                            });

                        } catch (e) {}
                    }, 800);
                })();
            """
           
            webView.evaluateJavaScript(jsScript, completionHandler: nil)
            webView.evaluateJavaScript("document.body.style.zoom = '\(parent.zoomLevel)%';", completionHandler: nil)
        }
    }
}
