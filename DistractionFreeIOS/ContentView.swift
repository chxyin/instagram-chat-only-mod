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
            // Instagram WKWebView Wrapper
            WebViewWrapper(
                zoomLevel: $zoomLevel,
                mediaAllowed: $mediaAllowed,
                webViewRef: $webView
            )
            .edgesIgnoringSafeArea(.all)
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
            .offset(x: CGFloat(offsetX) + currentDragOffset.width,
                    y: CGFloat(offsetY) + currentDragOffset.height)
            .padding(24)
            // Long Press and Drag implementation
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture())
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
                                offsetX += Double(drag.translation.width)
                                offsetY += Double(drag.translation.height)
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
        webViewRef = webView
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
                        a[href="/"],
                        a[href^="/explore/"],
                        a[href^="/reels/"],
                        a[href*="/camera/"],
                        a[href*="/direct/new"],
                        [aria-label="New message" i],
                        [aria-label="New chat" i],
                        svg[aria-label="New message" i],
                        svg[aria-label="New chat" i] {
                            display: none !important;
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

                            // Stop hiding stuff if on login page
                            if (path.includes('login') || path.includes('signup') || document.querySelector('input[name="username"]')) {
                                const mainFeed = document.querySelector('main');
                                if (mainFeed) mainFeed.style.removeProperty('display');
                                return;
                            }

                            if (path === '/') {
                                document.querySelectorAll('article').forEach(el => el.style.setProperty('display', 'none', 'important'));
                                const mainFeed = document.querySelector('main');
                                if (mainFeed) mainFeed.style.setProperty('display', 'none', 'important');
                                window.location.replace('/direct/');
                                return;
                            }
                           
                            if (path.startsWith('/direct')) {
                                const mainFeed = document.querySelector('main');
                                if (mainFeed) mainFeed.style.setProperty('display', 'flex', 'important');
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

                            const dmLink = document.querySelector('a[href^="/direct/"]');
                            if (dmLink) {
                                let navBar = dmLink.parentElement;
                                for (let i = 0; i < 5; i++) {
                                    if (!navBar || navBar.tagName === 'BODY') break;
                                    if (navBar.children.length > 2) {
                                        navBar.style.setProperty('justify-content', 'center', 'important');
                                        navBar.style.setProperty('width', '100%', 'important');
                                        navBar.style.setProperty('display', 'flex', 'important');
                                        Array.from(navBar.children).forEach(child => {
                                            if (!child.contains(dmLink)) {
                                                child.style.setProperty('display', 'none', 'important');
                                            }
                                        });
                                        break;
                                    }
                                    navBar = navBar.parentElement;
                                }
                            }

                            const textNodes = document.querySelectorAll('span, div, a, h2');
                            for (let el of textNodes) {
                                if (el.children.length === 0 && el.textContent) {
                                    const txt = el.textContent.trim().toLowerCase();

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

                            // Hide 'New Message' / 'New Chat' buttons
                            const newMsgBtns = document.querySelectorAll('[aria-label="New message" i], [aria-label="New chat" i], a[href*="/direct/new"]');
                            newMsgBtns.forEach(btn => {
                                let p = btn;
                                for (let i = 0; i < 4; i++) {
                                    if (!p || p.tagName === 'BODY' || (p.parentElement && p.parentElement.childElementCount > 1)) {
                                        break;
                                    }
                                    p = p.parentElement;
                                }
                               
                                if (p) {
                                    p.style.setProperty('display', 'none', 'important');
                                    p.style.setProperty('width', '0', 'important');
                                    p.style.setProperty('height', '0', 'important');
                                    p.style.setProperty('margin', '0', 'important');
                                    p.style.setProperty('padding', '0', 'important');
                                    p.style.setProperty('position', 'absolute', 'important');
                                    p.style.setProperty('pointer-events', 'none', 'important');
                                }
                               
                                if (p && p.parentElement) {
                                    p.parentElement.style.setProperty('display', 'none', 'important');
                                    p.parentElement.style.setProperty('width', '0', 'important');
                                    p.parentElement.style.setProperty('height', '0', 'important');
                                    p.parentElement.style.setProperty('margin', '0', 'important');
                                    p.parentElement.style.setProperty('padding', '0', 'important');
                                    p.parentElement.style.setProperty('position', 'absolute', 'important');
                                    p.parentElement.style.setProperty('pointer-events', 'none', 'important');
                                }
                                let grandP = p ? p.parentElement?.parentElement : null;
                                if (grandP) {
                                    grandP.style.setProperty('padding-bottom', '0', 'important');
                                    grandP.style.setProperty('margin-bottom', '0', 'important');
                                }
                            });

                            // Super aggressive Notes Nuke
                            if (window.location.pathname.startsWith('/direct')) {
                                const allDivs = document.querySelectorAll('div, ul');
                                for (let d of allDivs) {
                                    const text = d.textContent ? d.textContent.toLowerCase() : '';
                                    if (text.includes('your note') || text === 'notes' || text.includes('leave a note')) {
                                        const rect = d.getBoundingClientRect();
                                        if (rect.height > 60 && rect.height < 250 && rect.width > 100) {
                                            d.style.setProperty('display', 'none', 'important');
                                            d.style.setProperty('height', '0', 'important');
                                            d.style.setProperty('min-height', '0', 'important');
                                            d.style.setProperty('position', 'absolute', 'important');
                                            d.style.setProperty('opacity', '0', 'important');
                                            d.style.setProperty('pointer-events', 'none', 'important');
                                        }
                                    }
                                }
                            }
                        } catch (e) {}
                    }, 800);
                })();
            """
           
            webView.evaluateJavaScript(jsScript, completionHandler: nil)
            webView.evaluateJavaScript("document.body.style.zoom =
