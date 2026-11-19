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

    /// The whole page: the policy first, then the body as it came. `collapseQuote` folds the quoted history of a
    /// reply behind « Historique » (19/11), the signature folds behind « Signature » in every message, and the headers
    /// of a quoted or forwarded mail are made light: the app's own script does it, the HTML stays as it is. A plain
    /// text mail is cut by `MailPlainText` into parts the script folds the same way. The page has no background of
    /// its own: the mail sits on the app's (Paul, 14/11). In `dark`, the app's script darkens what is light.
    public static func document(body: String, isHTML: Bool, images: Bool, collapseQuote: Bool, dark: Bool = false) -> String {
        let content: String
        if isHTML {
            content = body
        } else {
            let parts = MailPlainText.parts(body)
            func block(_ text: String, _ mark: String = "") -> String {
                "<div\(mark) style=\"white-space:pre-wrap;font:15px/1.55 -apple-system,Helvetica,sans-serif\">\(linkified(escape(text)))</div>"
            }
            content = block(parts.text) + (parts.signature.map { block($0, " data-polhub-signature") } ?? "")
                + (parts.quote.map { block($0, " data-polhub-quote") } ?? "")
        }
        // Hidden until the script has adapted the colors: no white flash. CSS shows it anyway after a moment.
        let darkStyle = dark
            ? "html,body{color:#e3e3e3}a{color:#8ab4f8}body{visibility:hidden;animation:polhub-show 0s .8s forwards}@keyframes polhub-show{to{visibility:visible}}"
            : ""
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(policy(images: images))">
        <meta name="color-scheme" content="\(dark ? "dark" : "light only")">
        <style>html,body{margin:0;padding:0;background:transparent;color:#222;font:15px/1.5 Arial,Helvetica,sans-serif;overflow-wrap:break-word}\(foldStyle)\(darkStyle)</style>
        </head><body data-collapse="\(collapseQuote ? "1" : "0")" data-dark="\(dark ? "1" : "0")">\(content)</body></html>
        """
    }

    /// What is folded takes no room; a header of a quoted or forwarded mail is small and pale.
    /// The body holds its children's margins (`flow-root`): a first paragraph's top margin no longer escapes the
    /// measured height, which cut the last line (19/11).
    static let foldStyle = "body{display:flow-root}.polhub-folded{display:none !important}.polhub-light,.polhub-light *{font-size:12px !important;line-height:1.45 !important}"
        + ".polhub-light{opacity:.5}"

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
        var rules: [[String: Any]] = [["trigger": ["url-filter": "^https?://"], "action": ["type": "block"]]]
        if images {
            rules.append(["trigger": ["url-filter": "^https?://", "resource-type": ["image"]], "action": ["type": "ignore-previous-rules"]])
            // The known spy pixels stay blocked, images allowed or not (simplify-trackers).
            rules += MailTrackers.filters.map { ["trigger": ["url-filter": $0], "action": ["type": "block"]] }
        }
        let data = (try? JSONSerialization.data(withJSONObject: rules, options: [.withoutEscapingSlashes])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The app's own script, run in its own world while the mail's scripts stay off: the height of the page, a
    /// mail too wide made to fit, the real address of each link in its tooltip (with a warning when the text
    /// shows another site), the quoted history and the signature folded, the quoted headers made light.
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
          if (tag === 'IMG' || tag === 'SVG' || tag === 'VIDEO' || tag === 'PICTURE' || tag === 'BUTTON' && el.hasAttribute('data-polhub-fold')) continue;
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
      // Folding (Paul, 19/11): in a thread, each message shows what was written. The quoted history folds from where
      // it starts to the end, behind « Historique »; the signature behind « Signature »; the headers of a quoted or
      // forwarded mail are made light. Measured on real threads: Outlook marks its history only by a header block
      // (De / Envoyé or Date / À / Objet) under a grey rule, Gmail and Apple by a class or an attribution line, and a
      // history pasted flat can start in the middle of a paragraph. A forward stays; a mail that would show nothing
      // folds nothing.
      function norm(t) { return (t || '').replace(/[\u00a0\u202f\u2009\u200b]/g, ' ').replace(/\s+/g, ' ').trim(); }
      // An element's text as its lines read: a break or a block ends a line (Outlook writes its header lines in one
      // paragraph, split by <br>, and textContent glues « 14:20À : »). Only the first `limit` characters.
      function textOf(el, limit) {
        if (el.nodeType === 3) return el.nodeValue || '';
        var out = '', walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT), node;
        var max = limit || 4000;
        while ((node = walker.nextNode()) && out.length < max) {
          if (node.nodeType === 3) out += node.nodeValue;
          else if (node.tagName === 'BR' || /^(P|DIV|LI|TR|TD|BLOCKQUOTE|H[1-6]|TABLE|PRE)$/.test(node.tagName)) out += '\n';
        }
        return out;
      }
      function line(el, limit) { return norm(textOf(el, limit)); }
      var BLOCKS = 'p,div,blockquote,li,td,th,pre,h1,h2,h3,h4,h5,h6,table,ul,ol,hr';
      var reAttribution = [/^Le\s.{4,250}?(\d{1,2}[:h]\d{2}|\d{4}).{0,250}?\sa\s+écrit\s*:$/i,
                           /^On\s.{4,300}?(\d{1,2}:\d{2}|\d{4}).{0,300}?\bwrote\s*:$/i,
                           /^Am\s.{4,250}?(\d{1,2}:\d{2}|\d{4}).{0,250}?\sschrieb\b.{0,200}:$/i];
      var reOriginal = /^-{2,}\s*(Message d'origine|Message original|Mail original|Courriel original|Original Message|Ursprüngliche Nachricht)\s*-{2,}$/i;
      var reForward = /^(-{2,}\s*(Forwarded message|Message transféré|Mail transféré|Message transmis|Weitergeleitete Nachricht)\s*-{2,}|(Début du message (réexpédié|transféré)|Begin forwarded message)\s*:)/i;
      var reFrom = /^\*?(De|From|Von|Expéditeur)\s*\*?\s*:/i;
      var reWhen = /(^|\s)\*?(Envoyé( le| par)?|Sent|Date|Gesendet|Datum)\s*\*?\s*:[^:]{0,80}\d/i;
      var reOther = /(^|\s)\*?(À|A|To|An|Cc|Objet|Subject|Betreff|Sujet)\s*\*?\s*:/i;
      var reHeaderLine = /^\*?(De|From|Von|Expéditeur|Date|Envoyé( le| par)?|Sent|Gesendet|Datum|À|A|To|An|Cc|Cci|Bcc|Objet|Subject|Betreff|Sujet|Répondre à|Reply-To)\s*\*?\s*:/i;
      var reMobile = /^(Envoyé de mon (iPhone|iPad)|Envoyé depuis .{1,40}|Envoyé à partir de Outlook pour (iOS|Android)|Sent from my \w+.{0,20}|Sent from Outlook for (iOS|Android)|Get Outlook for (iOS|Android)|Obtenir Outlook pour (iOS|Android))/i;
      var reClosing = /^(cordialement|bien cordialement|très cordialement|bien à (vous|toi)|bonne (journée|soirée|fin de journée|semaine)|belle journée|à (bientôt|très vite|demain)|amicalement|amitiés|bises|merci( beaucoup| encore| d'avance)?|(sincères |meilleures )?salutations|best( regards| wishes)?|kind regards|warm regards|regards|many thanks.{0,30}|thanks.{0,20}|cheers|herzliche grüße|mit freundlichen grüßen|beste grüße|viele grüße)[\s,.!]*$/i;
      var reLegal = /(confidenti|destinataire|intended solely|privileged|Datenschutz|n'imprimez|the environment|l'environnement)/i;
      var reEvidence = [/(\+\d{2,3}|\b0)\s?\(?\d\)?([\s.\-]?\d{2}){4}/, /[\w.+-]+@[\w-]+\.\w/, /(www\.|https?:\/\/|\.(fr|com|net|org|io|eu|de|co)\b)/i,
                        /\b\d{1,4},?\s+(bis\s+|ter\s+)?(rue|avenue|av\.|boulevard|bd|place|allée|quai|chemin|impasse|cours)\b/i, /\b\d{5}\s+[A-Za-zÀ-ÿ]/, reLegal];
      function isAttribution(t) { for (var i = 0; i < reAttribution.length; i++) if (reAttribution[i].test(t)) return true; return false; }
      function isHeaderText(t) { return reFrom.test(t) && reWhen.test(t.slice(0, 700)) && reOther.test(t.slice(0, 900)); }
      // The blocks that hold no other block: the lines of a mail, in one pass.
      function leaves(root) {
        var blocks = root.querySelectorAll(BLOCKS), holders = new Set();
        for (var b = 0; b < blocks.length; b++) {
          for (var p = blocks[b].parentElement; p && p !== root && !holders.has(p); p = p.parentElement) holders.add(p);
        }
        return Array.prototype.filter.call(blocks, function (el) { return !holders.has(el); });
      }
      function precedes(a, b) { return !!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING); }
      function folded(el) { return !!(el.closest && el.closest('.polhub-folded')); }
      function isForward(el) { return (el.classList && el.classList.contains('moz-forward-container')) || reForward.test(line(el, 300)); }
      // Everything from `from` to `stop` (or the end), as the highest nodes that hold none of `stop`.
      function between(from, stop) {
        var out = [], node = from;
        while (node && node !== stop && node !== body) {
          if (stop && node.contains(stop)) { node = node.firstChild; continue; }
          out.push(node);
          while (node && node !== body && !node.nextSibling) node = node.parentNode;
          if (!node || node === body) break;
          node = node.nextSibling;
        }
        return out;
      }
      // Folded or shown; a text node gets a wrapper, a blank one is left.
      function wrapped(nodes) {
        var out = [];
        for (var i = 0; i < nodes.length; i++) {
          var n = nodes[i];
          if (n.nodeType === 3) {
            if (!/\S/.test(n.nodeValue)) continue;
            var span = document.createElement('span');
            n.parentNode.insertBefore(span, n);
            span.appendChild(n);
            n = span;
          }
          if (n.nodeType === 1) out.push(n);
        }
        return out;
      }
      function setFolded(nodes, on) { for (var i = 0; i < nodes.length; i++) nodes[i].classList.toggle('polhub-folded', on); }
      // What still reads once folded: the footer of a phone alone is nothing. Counted on the text itself: in dark
      // mode the page is invisible until the colors are adapted, and `innerText` would say nothing is left.
      function somethingLeft() {
        var out = '', walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT), node;
        while ((node = walker.nextNode()) && out.length < 300) {
          var parent = node.parentElement;
          if (!parent || parent.closest('.polhub-folded, style, script, title, [data-polhub-fold]')) continue;
          out += ' ' + node.nodeValue;
        }
        var text = norm(out);
        return text.length > 0 && !reMobile.test(text);
      }
      function pill(kind, label, nodes) {
        var button = document.createElement('button');
        button.setAttribute('data-polhub-fold', kind);
        button.textContent = label + ' ▾';
        button.title = kind === 'quote' ? 'Afficher les messages précédents cités' : 'Afficher la signature';
        button.setAttribute('style', 'display:block;width:max-content;margin:0;padding:1px 10px;border:0;border-radius:999px;background:rgba(128,128,128,0.16);color:inherit;opacity:0.8;font:12px/1.6 -apple-system,sans-serif;cursor:pointer');
        // Room above and below inside its holder, never as a margin: a margin at the end of the page escapes the
        // measured height and the button was cut.
        var holder = document.createElement('div');
        holder.setAttribute('data-polhub-fold-holder', kind);
        holder.setAttribute('style', 'display:block;padding:6px 0');
        holder.appendChild(button);
        nodes[0].parentNode.insertBefore(holder, nodes[0]);
        button.addEventListener('click', function () {
          var show = nodes[0].classList.contains('polhub-folded');
          setFolded(nodes, !show);
          button.textContent = label + (show ? ' ▴' : ' ▾');
          post();
        });
      }

      // Where the history may start, every candidate, the earliest kept.
      var quotes = [];
      var markers = '.gmail_quote, blockquote[type="cite"], .yahoo_quoted, [class*="yahoo_quoted"], .moz-cite-prefix, #divRplyFwdMsg, #appendonsend, '
        + '#mail-editor-reference-message-container, #OLK_SRC_BODY_SECTION, div[name="messageReplySection"], .protonmail_quote, .zmail_extra, '
        + '[data-marker="__QUOTED_TEXT__"], [data-marker="__HEADERS__"], hr#stopSpelling, hr#zwchr, [data-polhub-quote]';
      Array.prototype.forEach.call(document.querySelectorAll(markers), function (el) { quotes.push(el); });
      // Outlook on Windows: a header under a grey rule, with neither class nor id.
      Array.prototype.forEach.call(document.querySelectorAll('div[style*="border-top"], div[style*="border-block-start"]'), function (el) {
        var style = (el.getAttribute('style') || '').replace(/\s+/g, '').toLowerCase();
        if (/#e1e1e1|#b5c4df|rgb\(225,225,225\)|rgb\(229,229,229\)/.test(style) && reFrom.test(line(el, 60))) quotes.push(el);
      });
      // An attribution line, « -----Message d'origine----- », a forward's separator, a header block.
      var all = leaves(body);
      for (var i = 0; i < all.length && all.length <= 4000; i++) {
        var el = all[i], t = line(el, 1300);
        if (!t || t.length > 1200) continue;
        if (t.length <= 600 && (isAttribution(t) || reOriginal.test(t) || reForward.test(t))) { quotes.push(el); continue; }
        if (reFrom.test(t)) {
          var context = t;
          for (var sib = el.nextElementSibling, n = 0; sib && n < 5 && context.length < 900; sib = sib.nextElementSibling, n++) context += ' ' + line(sib, 400);
          if (isHeaderText(context)) quotes.push(el);
        }
      }
      // A history pasted flat: it starts in the middle of a long text.
      var reFlatHeader = /(Sent from Outlook for (iOS|Android)\S*\s*|Envoyé à partir de Outlook pour (iOS|Android)\S*\s*)?(_{10,}\s*)?\*?(From|De|Von)\s*\*?\s*:\s*.{1,200}?\s\*?(Sent|Envoyé|Date|Gesendet)\s*\*?\s*:/i;
      var reFlatAttribution = /(\bLe\s.{4,120}?\d{1,2}[:h]\d{2},?\s.{0,200}?\sa\s+écrit\s*:|\bOn\s.{4,160}?\d{1,2}:\d{2}.{0,200}?\bwrote\s*:)/i;
      var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT), textNode, cuts = [];
      while ((textNode = walker.nextNode())) {
        var value = textNode.nodeValue || '';
        if (value.length < 200) continue;
        var at = -1, found;
        if ((found = reFlatHeader.exec(value)) && found.index > 0) at = found.index;
        if ((found = reFlatAttribution.exec(value)) && found.index > 0 && (at < 0 || found.index < at)) at = found.index;
        if (at > 0 && /\S/.test(value.slice(0, at))) cuts.push([textNode, at]);
      }
      cuts.forEach(function (cut) {
        var rest = cut[0].splitText(cut[1]), span = document.createElement('span');
        rest.parentNode.insertBefore(span, rest);
        span.appendChild(rest);
        quotes.push(span);
      });
      quotes.sort(function (a, b) { return a === b ? 0 : (precedes(a, b) ? -1 : 1); });
      var start = null;
      for (var q = 0; q < quotes.length && !start; q++) if (!isForward(quotes[q])) start = quotes[q];
      // The attribution, the rule, the underscores or the phone's footer just above go with it.
      function previousBlock(node) {
        var p = node.previousSibling;
        while (p && ((p.nodeType === 3 && !/\S/.test(p.nodeValue)) || (p.nodeType === 1 && p.tagName === 'BR'))) p = p.previousSibling;
        return p && p.nodeType === 1 ? p : null;
      }
      for (var up = 0; start && up < 4; up++) {
        var prev = previousBlock(start);
        if (!prev) break;
        var pt = line(prev, 700);
        if (prev.tagName === 'HR' || prev.id === 'appendonsend' || /^_{10,}$/.test(pt) || (pt.length <= 600 && isAttribution(pt)) || (pt.length <= 80 && reMobile.test(pt))) start = prev;
        else break;
      }
      var quoteNodes = [];
      if (start && body.getAttribute('data-collapse') === '1') {
        quoteNodes = wrapped(between(start, null));
        setFolded(quoteNodes, true);
        if (!quoteNodes.length || !somethingLeft()) { setFolded(quoteNodes, false); quoteNodes = []; }
      }

      // The signature: a marked one, else « -- » near the end, else the block after a closing and a first name when it
      // holds a phone, an address, a site or a legal notice. Only in what was written, above the history.
      var signatureNodes = [];
      var signs = '.gmail_signature, [data-smartmail="gmail_signature"], #Signature, #signature, #ms-outlook-mobile-signature, .moz-signature, .moz-txt-sig, '
        + 'div[name="messageSignatureSection"], .protonmail_signature_block, #ymail_android_signature, [data-marker="__SIG_PRE__"], [data-polhub-signature]';
      var marked = Array.prototype.filter.call(document.querySelectorAll(signs), function (el) { return !folded(el) && (!start || precedes(el, start)); })[0];
      if (marked) {
        var nodes = [marked];
        var before = marked.previousSibling;
        while (before && ((before.nodeType === 3 && !/\S/.test(before.nodeValue)) || (before.nodeType === 1 && before.tagName === 'BR'))) before = before.previousSibling;
        if (before && before.nodeType === 1 && before.classList.contains('gmail_signature_prefix')) nodes.unshift(before);
        signatureNodes = nodes;
      } else {
        var own = all.filter(function (el) { return el.isConnected && !folded(el) && (!start || precedes(el, start)); });
        var sigStart = null;
        for (var d = own.length - 1; d >= Math.max(0, own.length - 16); d--) if (line(own[d], 10) === '--') { sigStart = own[d]; break; }
        if (!sigStart) {
          var closing = -1;
          for (var k = own.length - 1; k >= 0; k--) {
            var ct = line(own[k], 100);
            if (ct.length <= 60 && reClosing.test(ct)) { closing = k; break; }
          }
          var name = -1;
          for (var m2 = closing + 1; closing >= 0 && m2 < own.length; m2++) if (line(own[m2], 100)) { name = m2; break; }
          if (name > 0 && line(own[name], 100).length <= 40) {
            var tail = own.slice(name + 1), lines = 0, text = '', long = false, pictures = 0;
            for (var r = 0; r < tail.length; r++) {
              var tt = line(tail[r], 600);
              pictures += tail[r].getElementsByTagName('img').length;
              if (!tt) continue;
              lines++;
              text += tt + '\n';
              if (tt.length > 160 && !reLegal.test(tt)) long = true;
            }
            var proofs = 0;
            for (var e = 0; e < reEvidence.length; e++) if (reEvidence[e].test(text)) proofs++;
            if (!long && lines + Math.min(pictures, 1) >= 2 && (proofs >= 1 || pictures >= 1)) {
              for (var f = 0; f < tail.length; f++) if (line(tail[f], 10) || tail[f].getElementsByTagName('img').length) { sigStart = tail[f]; break; }
            }
          }
        }
        if (sigStart) signatureNodes = between(sigStart, start);
      }
      if (signatureNodes.length) {
        signatureNodes = wrapped(signatureNodes);
        setFolded(signatureNodes, true);
        if (!signatureNodes.length || !somethingLeft()) { setFolded(signatureNodes, false); signatureNodes = []; }
      }
      if (signatureNodes.length) pill('signature', 'Signature', signatureNodes);
      if (quoteNodes.length) pill('quote', 'Historique', quoteNodes);

      // The headers of a quoted or forwarded mail, light: an attribution, a separator, a header block, or two header
      // lines side by side.
      var marks = document.querySelectorAll('.gmail_attr, .moz-cite-prefix, #divRplyFwdMsg, table.moz-email-headers-table');
      Array.prototype.forEach.call(marks, function (el) { el.classList.add('polhub-light'); });
      function near(x) { return x >= 0 && x < all.length && reHeaderLine.test(line(all[x], 200)); }
      for (var h = 0; h < all.length && all.length <= 4000; h++) {
        var ht = line(all[h], 1000);
        if (!ht || ht.length > 900) continue;
        if ((ht.length <= 600 && (isAttribution(ht) || reForward.test(ht) || reOriginal.test(ht))) || isHeaderText(ht)
            || (reHeaderLine.test(ht) && ht.length <= 200 && (near(h - 1) || near(h + 1)))) all[h].classList.add('polhub-light');
      }
      body.setAttribute('data-polhub-folded', '1');
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
