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
            Color(UIColor.systemBackground).ignoresSafeArea()
            
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
    @Binding var mediaAllowed: Bool
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
                        body { margin: 0 !important; padding: 0 !important; }
                        
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

                        /* Smoother general animations and scrolling */
                        html, body {
                            scroll-behavior: smooth !important;
                            -webkit-overflow-scrolling: touch !important;
                        }

                        a, button, div[role="button"] {
                            transition: transform 0.2s cubic-bezier(0.25, 0.1, 0.25, 1), opacity 0.2s ease-in-out !important;
                        }

                        /* Keyboard Dismiss Button */
                        #df-dismiss-kb {
                            position: fixed;
                            bottom: 55vh; /* Places it clearly above the keyboard */
                            right: 15px;
                            width: 50px;
                            height: 50px;
                            background: rgba(30, 30, 30, 0.8);
                            backdrop-filter: blur(10px);
                            -webkit-backdrop-filter: blur(10px);
                            border: 1px solid rgba(255,255,255,0.2);
                            border-radius: 25px;
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            font-size: 24px;
                            z-index: 99999999;
                            opacity: 0;
                            transform: scale(0.8);
                            pointer-events: none;
                            transition: opacity 0.3s ease, transform 0.3s ease;
                            box-shadow: 0 4px 15px rgba(0,0,0,0.5);
                            color: white;
                        }
                        #df-dismiss-kb.df-kb-visible {
                            opacity: 1 !important;
                            transform: scale(1.0) !important;
                            pointer-events: auto !important;
                        }
                    `;
                    document.head.appendChild(style);

                    // 1.5 KEYBOARD DISMISS LOGIC
                    const kbBtn = document.createElement('div');
                    kbBtn.id = 'df-dismiss-kb';
                    kbBtn.innerHTML = '⬇️';
                    document.body.appendChild(kbBtn);

                    const dismissAction = (e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        if (document.activeElement) document.activeElement.blur();
                        document.querySelectorAll('[contenteditable="true"], textarea, input').forEach(el => el.blur());
                        kbBtn.classList.remove('df-kb-visible');
                    };

                    kbBtn.addEventListener('mousedown', dismissAction);
                    kbBtn.addEventListener('touchstart', dismissAction);

                    const updateKbPos = () => {
                        if (!kbBtn.classList.contains('df-kb-visible')) return;
                        
                        // Find the Instagram sticker/emoji button to place the dismiss button EXACTLY over it
                        const svgs = Array.from(document.querySelectorAll('svg'));
                        const stickerSvgs = svgs.filter(s => {
                            const lbl = s.getAttribute('aria-label');
                            return lbl && (lbl.toLowerCase().includes('emoji') || lbl.toLowerCase().includes('sticker'));
                        });
                        
                        const sticker = stickerSvgs[stickerSvgs.length - 1]; // bottom one inside DM bar
                        if (sticker) {
                            const r = sticker.getBoundingClientRect();
                            kbBtn.style.position = 'fixed';
                            kbBtn.style.top = (r.top - 6) + 'px';
                            kbBtn.style.left = (r.left - 6) + 'px';
                            kbBtn.style.width = (r.width + 12) + 'px';
                            kbBtn.style.height = (r.height + 12) + 'px';
                            kbBtn.style.bottom = 'auto';
                            kbBtn.style.right = 'auto';
                            kbBtn.style.background = 'rgba(120, 120, 120, 0.4)';
                            kbBtn.style.backdropFilter = 'blur(10px)';
                            kbBtn.style.WebkitBackdropFilter = 'blur(10px)';
                            kbBtn.style.borderRadius = '50%';
                        } else {
                            // default fallback
                            kbBtn.style.bottom = '55vh';
                            kbBtn.style.right = '15px';
                            kbBtn.style.top = 'auto';
                            kbBtn.style.left = 'auto';
                            kbBtn.style.width = '40px';
                            kbBtn.style.height = '40px';
                        }
                    };

                    document.addEventListener('focusin', (e) => {
                        const tag = e.target.tagName;
                        if (tag === 'TEXTAREA' || tag === 'INPUT' || e.target.isContentEditable || e.target.getAttribute('contenteditable') === 'true' || e.target.getAttribute('role') === 'textbox') {
                            kbBtn.classList.add('df-kb-visible');
                            setTimeout(updateKbPos, 100);
                            setTimeout(updateKbPos, 400);
                        }
                    });

                    document.addEventListener('focusout', (e) => {
                        setTimeout(() => {
                            const act = document.activeElement;
                            if (!act || (act.tagName !== 'TEXTAREA' && act.tagName !== 'INPUT' && !act.isContentEditable && act.getAttribute('contenteditable') !== 'true' && act.getAttribute('role') !== 'textbox')) {
                                kbBtn.classList.remove('df-kb-visible');
                            }
                        }, 200);
                    });

                    // Track keyboard resizes to keep the button placed perfectly over the sticker menu
                    window.visualViewport.addEventListener('resize', updateKbPos);
                    window.visualViewport.addEventListener('scroll', updateKbPos);

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

                            // 1. Delete Notes in DM Inbox
                            if (path.startsWith('/direct')) {
                                const texts = document.querySelectorAll('span, div');
                                for (let el of texts) {
                                    if (el.children.length === 0 && el.textContent) {
                                        const txt = el.textContent.trim().toLowerCase();
                                        if (txt === 'notes' || txt.includes('your note') || txt.includes('leave a note')) {
                                            let p = el;
                                            for (let i = 0; i < 8; i++) {
                                                if (!p || p.tagName === 'BODY' || p.tagName === 'MAIN') break;
                                                // Identify the horizontally scrolling notes tray or its direct large container
                                                if (p.style.overflowX === 'auto' || p.style.overflowX === 'scroll' || p.tagName === 'UL') {
                                                    p.style.setProperty('display', 'none', 'important');
                                                    break;
                                                }
                                                // General heuristic for the tray container
                                                if (p.offsetHeight > 80 && p.offsetHeight < 180 && p.offsetWidth > window.innerWidth * 0.8) {
                                                    p.style.setProperty('display', 'none', 'important');
                                                    break;
                                                }
                                                p = p.parentElement;
                                            }
                                        }
                                    }
                                }
                            }

                            // 2. Mod Home Page: Only Stories, Centered and Enlarged
                            if (path === '/') {
                                // Hide all feed posts
                                document.querySelectorAll('article').forEach(el => {
                                    el.style.setProperty('display', 'none', 'important');
                                    if (el.parentElement) el.parentElement.style.setProperty('display', 'none', 'important');
                                });

                                // Center the Stories Tray to fill the empty space
                                const ul = document.querySelector('ul');
                                if (ul) {
                                    ul.style.setProperty('transform', 'scale(1.3)', 'important');
                                    ul.style.setProperty('transform-origin', 'top center', 'important');
                                    ul.style.setProperty('margin-top', '15vh', 'important');
                                    ul.style.setProperty('justify-content', 'center', 'important');
                                    
                                    let p = ul.parentElement;
                                    if (p) {
                                        p.style.setProperty('height', '70vh', 'important');
                                        p.style.setProperty('display', 'flex', 'important');
                                        p.style.setProperty('flex-direction', 'column', 'important');
                                    }
                                }
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
