import Foundation

/// JavaScript run inside an agent's private browser. Every snippet returns a JSON string so the Swift side can
/// merge it into the tool result without caring about WebKit's bridging rules.
enum BrowserScripts {
    static func literal(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
            let array = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    static let state = """
        JSON.stringify({
          url: location.href, title: document.title,
          text_preview: (document.body ? document.body.innerText : '').replace(/\\s+/g, ' ').trim().slice(0, 1500)
        })
        """

    static let text = "(document.body ? document.body.innerText : '')"

    static let html = "document.documentElement.outerHTML"

    static let links = """
        JSON.stringify(Array.from(document.querySelectorAll('a[href]')).slice(0, 300).map(a => ({
          text: (a.innerText || a.getAttribute('aria-label') || '').replace(/\\s+/g, ' ').trim().slice(0, 120),
          href: a.href
        })))
        """

    static func click(selector: String, text: String) -> String {
        """
        (() => {
          const sel = \(literal(selector)), txt = \(literal(text));
          const norm = s => (s || '').replace(/\\s+/g, ' ').trim().toLowerCase();
          const visible = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
          let el = null;
          if (sel) {
            el = document.querySelector(sel);
            if (!el) return JSON.stringify({error: 'no element matches selector ' + sel});
          } else {
            const want = norm(txt);
            const label = e => norm(e.innerText || e.value || e.getAttribute('aria-label') || e.getAttribute('title'));
            const cands = Array.from(document.querySelectorAll(
              'a, button, input[type=submit], input[type=button], [role=button], [role=link], [role=tab], [role=menuitem], label, summary, [onclick]'
            )).filter(visible);
            el = cands.find(e => label(e) === want) || cands.find(e => label(e).includes(want));
            if (!el) {
              const leaves = Array.from(document.querySelectorAll('body *')).filter(e => visible(e) && e.children.length === 0);
              el = leaves.find(e => norm(e.textContent) === want) || leaves.find(e => norm(e.textContent).includes(want));
            }
            if (!el) return JSON.stringify({error: 'no visible element with text ' + JSON.stringify(txt)});
          }
          el.scrollIntoView({block: 'center', inline: 'center'});
          const r = el.getBoundingClientRect();
          const opts = {bubbles: true, cancelable: true, view: window, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2};
          for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) el.dispatchEvent(new MouseEvent(type, opts));
          el.click();
          return JSON.stringify({
            clicked: el.tagName.toLowerCase() + (el.id ? '#' + el.id : ''),
            element_text: (el.innerText || el.value || '').replace(/\\s+/g, ' ').trim().slice(0, 80)
          });
        })()
        """
    }

    static func type(selector: String, text: String, submit: Bool) -> String {
        """
        (() => {
          const sel = \(literal(selector)), txt = \(literal(text)), submit = \(submit ? "true" : "false");
          const visible = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
          const editable = e => !!e && (e.tagName === 'INPUT' || e.tagName === 'TEXTAREA' || e.isContentEditable);
          let el = sel ? document.querySelector(sel) : document.activeElement;
          if (sel && !el) return JSON.stringify({error: 'no element matches selector ' + sel});
          if (!editable(el)) {
            el = Array.from(document.querySelectorAll(
              'input:not([type=hidden]):not([type=submit]):not([type=button]):not([type=checkbox]):not([type=radio]), textarea, [contenteditable=true], [contenteditable=""]'
            )).find(visible);
          }
          if (!el) return JSON.stringify({error: 'no editable element found; pass a selector'});
          el.focus();
          if (el.isContentEditable) {
            document.execCommand('selectAll', false, null);
            document.execCommand('insertText', false, txt);
          } else {
            const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
            setter.call(el, txt);
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
          }
          if (submit) {
            const key = {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true};
            const prevented = !el.dispatchEvent(new KeyboardEvent('keydown', key));
            el.dispatchEvent(new KeyboardEvent('keypress', key));
            el.dispatchEvent(new KeyboardEvent('keyup', key));
            if (!prevented && el.form) { if (el.form.requestSubmit) el.form.requestSubmit(); else el.form.submit(); }
          }
          return JSON.stringify({
            typed: txt.length,
            element: el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.name ? '[name=' + el.name + ']' : '')
          });
        })()
        """
    }
}
