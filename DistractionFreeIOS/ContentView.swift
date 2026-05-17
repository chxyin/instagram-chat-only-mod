import SwiftUI
import WebKit
import Combine

struct ContentView: View {
    @AppStorage("zoomLevel") private var zoomLevel: Int = 100
    @AppStorage("offsetX") private var offsetX: Double = 0.0
    @AppStorage("offsetY") private var offsetY: Double = 0.0
   
    @State private var screenTimeSeconds: Int = 0
    @State private var currentDayString: String = ""
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
            Color(UIColor.systemBackground).ignoresSafeArea()
            
            // Instagram WKWebView Wrapper
            WebViewWrapper(
                zoomLevel: $zoomLevel,
                webViewRef: $webView
            )
            .onAppear {
                currentDayString = todayKey
                screenTimeSeconds = UserDefaults.standard.integer(forKey: currentDayString)
            }
            .onReceive(timer) { _ in
                let currentDay = todayKey
                if currentDay != currentDayString { // Reset at 00:00 midnight automatically
                    currentDayString = currentDay
                    screenTimeSeconds = 0
                }
                screenTimeSeconds += 1
                if screenTimeSeconds % 10 == 0 {
                    UserDefaults.standard.set(screenTimeSeconds, forKey: currentDayString)
                }
            }
           
            // Screen Time / Menu FAB
            Menu {
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
            // Instant Drag implementation
            .simultaneousGesture(
                DragGesture(minimumDistance: 0.0, coordinateSpace: .local)
                    .onChanged { drag in
                        currentDragOffset = drag.translation
                    }
                    .onEnded { drag in
                        let newX = CGFloat(offsetX) + drag.translation.width
                        let newY = CGFloat(offsetY) + drag.translation.height
                        
                        offsetX = Double(max(-21, min(newX, UIScreen.main.bounds.width - 130)))
                        offsetY = Double(max(-UIScreen.main.bounds.height + 100, min(newY, 21)))
                        currentDragOffset = .zero
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
    @Binding var webViewRef: WKWebView?
   
    func makeUIView(context: Context) -> WKWebView {
        // Force massive memory and disk cache to speed up navigation and chat loading
        let sharedCache = URLCache(
            memoryCapacity: 512 * 1024 * 1024, // 512 MB Memory Cache
            diskCapacity: 2 * 1024 * 1024 * 1024, // 2 GB Disk Cache
            directory: nil
        )
        URLCache.shared = sharedCache

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
       
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        
        DispatchQueue.main.async {
            webViewRef = webView
        }
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
       
        if let url = URL(string: "https://www.instagram.com/direct/inbox/") {
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
       
        // Native URL Intercept - catches hard navigations instantly before they use any network
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let path = url.path
                if path == "/" || path.hasPrefix("/reels/") {
                    decisionHandler(.cancel)
                    if let inbox = URL(string: "https://www.instagram.com/direct/inbox/") {
                        webView.load(URLRequest(url: inbox))
                    }
                    return
                }
            }
            decisionHandler(.allow)
        }
       
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let jsScript = """
                javascript:(function() {
                    if (window.distractionFreeInitialized) return;
                    window.distractionFreeInitialized = true;

                    // 1. INSTANT PRELOAD METHOD: Prefetch links ~300ms before they are actualized
                    let preloadedUrls = new Set();
                    document.addEventListener('touchstart', (e) => {
                        let link = e.target.closest('a');
                        if (!link && e.target.parentElement) {
                            link = e.target.parentElement.closest('a');
                        }
                        if (link && link.href && link.href.startsWith(window.location.origin) && !preloadedUrls.has(link.href)) {
                            preloadedUrls.add(link.href);
                            const prefetch = document.createElement('link');
                            prefetch.rel = 'prefetch';
                            prefetch.href = link.href;
                            prefetch.as = 'document';
                            document.head.appendChild(prefetch);
                        }
                    }, { passive: true });

                    // 2. SPA ROUTER INTERCEPT: Instantly block Instagram React navigations
                    const originalPushState = history.pushState;
                    const originalReplaceState = history.replaceState;
                    
                    const handleUrlChange = (url) => {
                        if (!url) return false;
                        let targetPath = '';
                        try {
                            const parsed = new URL(url, window.location.origin);
                            targetPath = parsed.pathname;
                        } catch(e) { targetPath = url; }
                        
                        if (targetPath === '/' || targetPath.startsWith('/reels/')) {
                            window.location.replace('/direct/inbox/');
                            return true;
                        }
                        return false;
                    };

                    history.pushState = function(state, unused, url) {
                        if (handleUrlChange(url)) return;
                        return originalPushState.apply(this, arguments);
                    };

                    history.replaceState = function(state, unused, url) {
                        if (handleUrlChange(url)) return;
                        return originalReplaceState.apply(this, arguments);
                    };

                    window.addEventListener('popstate', () => {
                        handleUrlChange(window.location.href);
                    });

                    // 3. Fallback path observer (cleans up any straggling DOM events instantly)
                    let dfObserverTimeout = null;
                    const applyDFRules = () => {
                        try {
                            const path = window.location.pathname;
                            if (path === '/' || path.startsWith('/reels/')) {
                                window.location.replace('/direct/inbox/');
                            }
                        } catch (e) {
                            console.error(e);
                        }
                    };

                    const dfObserver = new MutationObserver(() => {
                        if (dfObserverTimeout) clearTimeout(dfObserverTimeout);
                        dfObserverTimeout = setTimeout(applyDFRules, 50); // Lowered debounce for faster fallback
                    });
                    
                    dfObserver.observe(document.body, { childList: true, subtree: true });
                    applyDFRules();
                })();
            """
           
            webView.evaluateJavaScript(jsScript, completionHandler: nil)
            webView.evaluateJavaScript("document.body.style.zoom = '\(parent.zoomLevel)%';", completionHandler: nil)
        }
    }
}
