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
    /// reply behind « ••• » (the app's own script does it, the HTML stays as it is).
    public static func document(body: String, isHTML: Bool, images: Bool, collapseQuote: Bool) -> String {
        let content = isHTML ? body : "<div style=\"white-space:pre-wrap;font:13px/1.5 -apple-system,Helvetica,sans-serif\">\(linkified(escape(body)))</div>"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(policy(images: images))">
        <meta name="color-scheme" content="light only">
        <style>html,body{margin:0;padding:0;background:#fff;color:#222;font:small/1.5 Arial,Helvetica,sans-serif;overflow-wrap:break-word}</style>
        </head><body data-collapse="\(collapseQuote ? "1" : "0")">\(content)</body></html>
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
            button.setAttribute('style', 'display:block;margin:10px 0;padding:0 8px;border:0;border-radius:6px;background:#e8eaed;color:#444;font:13px/1.4 -apple-system,sans-serif;cursor:pointer');
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
      fit(); post();
      window.addEventListener('load', function () { fit(); post(); });
      for (var j = 0; j < document.images.length; j++) document.images[j].addEventListener('load', function () { fit(); post(); });
      if (window.ResizeObserver) new ResizeObserver(function () { post(); }).observe(body);
      window.addEventListener('resize', function () { body.style.zoom = ''; fit(); post(); });
    })();
    """#
}
