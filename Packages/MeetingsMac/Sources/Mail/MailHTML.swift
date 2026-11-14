import Foundation

/// The page a message is shown in (14/11). The sender's HTML is never rewritten: it is only wrapped, behind a
/// content policy that lets nothing load but what Paul allowed.
public enum MailHTML {
    /// What the page may load: nothing, but the images joined to the mail, and the remote ones when allowed.
    /// No script, no frame, no font, no form, no remote style sheet.
    public static func policy(images: Bool) -> String {
        "default-src 'none'; img-src cid: data:\(images ? " https: http:" : ""); style-src 'unsafe-inline'; font-src 'none'; "
            + "media-src 'none'; form-action 'none'; base-uri 'none'"
    }

    /// The whole page: the policy first, then the body as it came. `collapseQuote` hides the quoted text of a
    /// reply behind « ••• » (the app's own script does it, the HTML stays as it is). The page has no background
    /// of its own: the mail sits on the app's (Paul, 14/11). In `dark`, the app's script darkens what is light.
    public static func document(body: String, isHTML: Bool, images: Bool, collapseQuote: Bool, dark: Bool = false) -> String {
        let content = isHTML ? body : "<div style=\"white-space:pre-wrap;font:13px/1.5 -apple-system,Helvetica,sans-serif\">\(linkified(escape(body)))</div>"
        // Hidden until the script has adapted the colors: no white flash. CSS shows it anyway after a moment.
        let darkStyle = dark
            ? "html,body{color:#e3e3e3}a{color:#8ab4f8}body{visibility:hidden;animation:polhub-show 0s .8s forwards}@keyframes polhub-show{to{visibility:visible}}"
            : ""
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(policy(images: images))">
        <meta name="color-scheme" content="\(dark ? "dark" : "light only")">
        <style>html,body{margin:0;padding:0;background:transparent;color:#222;font:small/1.5 Arial,Helvetica,sans-serif;overflow-wrap:break-word}\(darkStyle)</style>
        </head><body data-collapse="\(collapseQuote ? "1" : "0")" data-dark="\(dark ? "1" : "0")">\(content)</body></html>
        """
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The addresses of a plain text mail become links (the text is already escaped).
    static func linkified(_ escaped: String) -> String {
        escaped.replacingOccurrences(of: #"https?://[^\s<>"]+[^\s<>".,;:!?)]"#, with: "<a href=\"$0\">$0</a>", options: .regularExpression)
    }

    /// Whether the body asks for images from elsewhere: only then is « Afficher les images » worth showing.
    public static func hasRemoteImages(_ body: String) -> Bool {
        body.range(of: #"(<img[^>]+src\s*=\s*["']?https?://)|(url\(\s*["']?https?://)|(background\s*=\s*["']?https?://)"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The second lock, WebKit's own content rules: every remote load is blocked, but the images when allowed.
    public static func contentRules(images: Bool) -> String {
        let block = #"{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}"#
        let allow = #"{"trigger":{"url-filter":"^https?://","resource-type":["image"]},"action":{"type":"ignore-previous-rules"}}"#
        return "[\(block)\(images ? ",\(allow)" : "")]"
    }

    /// The app's own script, run in its own world while the mail's scripts stay off: the height of the page, a
    /// mail too wide made to fit, the real address of each link in its tooltip (with a warning when the text
    /// shows another site), and the quoted text behind « ••• ».
    public static let readerScript = #"""
    (function () {
      var body = document.body, root = document.documentElement;
      if (!body) return;
      function rgba(text) {
        var m = /rgba?\(([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s\/]+([\d.]+%?))?/.exec(text || '');
        if (!m) return null;
        var a = m[4] === undefined ? 1 : (m[4].slice(-1) === '%' ? parseFloat(m[4]) / 100 : parseFloat(m[4]));
        return { r: +m[1], g: +m[2], b: +m[3], a: a };
      }
      function luminance(c) {
        function f(v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
      }
      function hsl(c) {
        var r = c.r / 255, g = c.g / 255, b = c.b / 255, max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, h = 0, s = 0;
        if (max !== min) {
          var d = max - min;
          s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
          h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
          h /= 6;
        }
        return { h: h, s: s, l: l };
      }
      function css(h, s, l, a) {
        return 'hsla(' + Math.round(h * 360) + ',' + Math.round(s * 100) + '%,' + Math.round(l * 100) + '%,' + a + ')';
      }
      // Dark mode, as Apple Mail does it, without touching the HTML: a mail that has its own dark style keeps it;
      // otherwise light backgrounds go dark (near-white ones take the app's own) and dark texts go light, each
      // keeping its hue. Images stay as they are, and so does what sits on a background image.
      function darken() {
        if (body.getAttribute('data-dark') !== '1') return;
        // Only the mail's own tags count: Polhub's page says « dark » in its head, the mail sits in the body.
        var own = body.querySelector('meta[name="color-scheme"][content*="dark"],meta[name="supported-color-schemes"][content*="dark"]');
        var styles = body.querySelectorAll('style');
        for (var i = 0; i < styles.length && !own; i++) if (/prefers-color-scheme\s*:\s*dark/i.test(styles[i].textContent)) own = styles[i];
        if (own) return;
        // A mail made almost only of images (a promotion) stays on light: darkening around its pictures would
        // leave white blocks on black. The app shows it on a light card.
        // All the text, folded quotes and hidden parts included: a short reply above a long quote is not a
        // mail of images.
        var words = (body.textContent || '').replace(/\s+/g, ' ').trim().length;
        if (document.images.length >= 2 && words < 200) {
          try { window.webkit.messageHandlers.polhub.postMessage({ light: true }); } catch (e) {}
          return;
        }
        var all = [body].concat(Array.prototype.slice.call(body.getElementsByTagName('*'))), plan = [];
        for (var k = 0; k < all.length; k++) {
          var el = all[k], tag = el.tagName;
          if (tag === 'IMG' || tag === 'SVG' || tag === 'VIDEO' || tag === 'PICTURE' || tag === 'BUTTON' && el.textContent === '•••') continue;
          if (el.closest('[data-polhub-keep]')) continue;
          var cs = getComputedStyle(el);
          if (cs.backgroundImage && cs.backgroundImage !== 'none' && cs.backgroundImage.indexOf('gradient') < 0) { el.setAttribute('data-polhub-keep', '1'); continue; }
          var bg = rgba(cs.backgroundColor), fg = rgba(cs.color), border = rgba(cs.borderTopColor), change = { el: el };
          if (bg && bg.a > 0.05 && luminance(bg) > 0.35) {
            var b = hsl(bg);
            // A vivid color (a brand's button) stays as it is, and so does the text written on it.
            if (b.s > 0.45 && b.l < 0.8) el.setAttribute('data-polhub-vivid', '1');
            else change.bg = b.l > 0.93 && b.s < 0.2 ? 'transparent' : css(b.h, Math.min(b.s, 0.6), Math.max(0.1, Math.min(0.28, 1 - b.l)), bg.a);
          }
          if (fg && luminance(fg) < 0.3 && !el.closest('[data-polhub-vivid]')) {
            var t = hsl(fg);
            change.fg = css(t.h, Math.min(t.s, 0.8), Math.max(0.72, Math.min(0.92, 1 - t.l)), fg.a);
          }
          if (border && border.a > 0 && parseFloat(cs.borderTopWidth) > 0 && luminance(border) > 0.6) change.border = 'rgba(255,255,255,0.14)';
          if (change.bg || change.fg || change.border) plan.push(change);
        }
        // Read everything first, then write: one style computation instead of one per element.
        for (var p = 0; p < plan.length; p++) {
          var c = plan[p], st = c.el.style;
          if (c.bg) st.setProperty('background-color', c.bg, 'important');
          if (c.fg) st.setProperty('color', c.fg, 'important');
          if (c.border) st.setProperty('border-color', c.border, 'important');
        }
      }
      function post() {
        // The body's own height, never the window's: the frame can shrink again when the quoted text folds.
        var zoom = parseFloat(body.style.zoom) || 1;
        var height = Math.max(body.getBoundingClientRect().height, body.scrollHeight * zoom);
        try { window.webkit.messageHandlers.polhub.postMessage({ height: Math.ceil(height) }); } catch (e) {}
      }
      function fit() {
        var wide = root.scrollWidth, room = root.clientWidth;
        if (room > 0 && wide > room + 2) body.style.zoom = String(room / wide);
      }
      var links = document.querySelectorAll('a[href]');
      for (var i = 0; i < links.length; i++) {
        var link = links[i], href = link.getAttribute('href') || '', title = href;
        var shown = (link.textContent || '').trim().match(/^(https?:\/\/)?([a-z0-9-]+(\.[a-z0-9-]+)+)(\/|$)/i);
        if (shown) {
          try {
            var host = new URL(href, 'https://x.invalid').hostname.replace(/^www\./, '');
            var seen = shown[2].toLowerCase().replace(/^www\./, '');
            if (host && host !== 'x.invalid' && host !== seen && !host.endsWith('.' + seen)) {
              title = 'Attention : ce lien affiche « ' + seen + ' » mais mène à ' + host;
              link.setAttribute('data-polhub-warning', '1');
            }
          } catch (e) {}
        }
        link.setAttribute('title', title);
      }
      if (body.getAttribute('data-collapse') === '1') {
        var quote = document.querySelector('.gmail_quote, blockquote[type="cite"], .yahoo_quoted, .moz-cite-prefix, #divRplyFwdMsg, #appendonsend');
        if (quote && quote.parentNode) {
          var hidden = [quote];
          if (quote.id === 'divRplyFwdMsg' || quote.id === 'appendonsend' || (' ' + quote.className + ' ').indexOf(' moz-cite-prefix ') >= 0) {
            for (var next = quote.nextElementSibling; next; next = next.nextElementSibling) hidden.push(next);
          }
          var quoted = 0;
          for (var k = 0; k < hidden.length; k++) quoted += (hidden[k].textContent || '').trim().length;
          if ((body.textContent || '').trim().length - quoted > 0) {
            var button = document.createElement('button');
            button.textContent = '•••';
            button.title = 'Afficher le texte cité';
            button.setAttribute('style', 'display:block;margin:10px 0;padding:0 8px;border:0;border-radius:6px;background:rgba(128,128,128,0.2);color:inherit;font:13px/1.4 -apple-system,sans-serif;cursor:pointer');
            for (var m = 0; m < hidden.length; m++) hidden[m].style.display = 'none';
            quote.parentNode.insertBefore(button, quote);
            button.addEventListener('click', function () {
              var show = hidden[0].style.display === 'none';
              for (var n = 0; n < hidden.length; n++) hidden[n].style.display = show ? '' : 'none';
              post();
            });
          }
        }
      }
      try { darken(); } catch (e) {}
      body.style.visibility = 'visible';
      fit(); post();
      window.addEventListener('load', function () { fit(); post(); });
      for (var j = 0; j < document.images.length; j++) document.images[j].addEventListener('load', function () { fit(); post(); });
      if (window.ResizeObserver) new ResizeObserver(function () { post(); }).observe(body);
      window.addEventListener('resize', function () { body.style.zoom = ''; fit(); post(); });
    })();
    """#
}
