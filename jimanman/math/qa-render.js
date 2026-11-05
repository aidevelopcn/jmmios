(function () {
  if (!Array.prototype.at) {
    Array.prototype.at = function (n) {
      n = Math.trunc(Number(n)) || 0;
      if (n < 0) n += this.length;
      if (n < 0 || n >= this.length) return undefined;
      return this[n];
    };
  }
  if (window.marked && marked.setOptions) {
    marked.setOptions({ breaks: true, gfm: true });
  }
  function parseMarkdown(src) {
    try {
      var m = window.marked;
      if (m && typeof m.parse === "function") return m.parse(src);
      if (typeof m === "function") return m(src);
      if (m && m.marked && typeof m.marked.parse === "function") return m.marked.parse(src);
    } catch (e) {}
    return fallbackMarkdown(src);
  }
  function fallbackMarkdown(s) {
    var t = escapeHtml(String(s || ""));
    t = t.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
    t = t.replace(/^### (.+)$/gm, "<h3>$1</h3>");
    t = t.replace(/^## (.+)$/gm, "<h2>$1</h2>");
    t = t.replace(/^# (.+)$/gm, "<h1>$1</h1>");
    t = t.replace(/\n/g, "<br>");
    return t;
  }
  var DOL = String.fromCharCode(36);
  var BS = String.fromCharCode(92);
  var PHONE_REWRITE = false;
  var katexMemo = Object.create(null);
  var lastClosed = "\u0001";
  var paintedMd = "";
  function escapeHtml(s) {
    return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  function isMultiLineLatex(src) {
    return /\\\\|\\begin\{(?:aligned|align\*?|split|gather\*?|multline\*?|cases|array|matrix|pmatrix|bmatrix|vmatrix|Bmatrix|smallmatrix|gathered)\}/.test(src);
  }
  function maskUnclosed(md) {
    var s = String(md || "");
    var n = s.length, i = 0, openAt = -1, kind = "";
    while (i < n) {
      var c = s.charAt(i), n1 = s.charAt(i + 1);
      if (c === DOL && n1 === DOL) {
        if (kind === "dd") { kind = ""; openAt = -1; }
        else if (kind === "") { kind = "dd"; openAt = i; }
        i += 2; continue;
      }
      if (c === DOL) {
        if (kind === "d") { kind = ""; openAt = -1; }
        else if (kind === "") { kind = "d"; openAt = i; }
        i += 1; continue;
      }
      if (c === BS && n1 === "[") { if (kind === "") { kind = "br"; openAt = i; } i += 2; continue; }
      if (c === BS && n1 === "]") { if (kind === "br") { kind = ""; openAt = -1; } i += 2; continue; }
      if (c === BS && n1 === "(") { if (kind === "") { kind = "p"; openAt = i; } i += 2; continue; }
      if (c === BS && n1 === ")") { if (kind === "p") { kind = ""; openAt = -1; } i += 2; continue; }
      i += 1;
    }
    if (openAt < 0) return { body: s, tail: "" };
    return { body: s.slice(0, openAt), tail: s.slice(openAt) };
  }
  function wrapBareEnvs(md) {
    var re = new RegExp(BS + "begin\\{([a-zA-Z*]+)\\}([\\s\\S]*?)" + BS + "end\\{\\1\\}", "g");
    return String(md || "").replace(re, function (m, env, body, offset, src) {
      var before = src.slice(Math.max(0, offset - 2), offset);
      if (before === DOL + DOL) return m;
      return DOL + DOL + m + DOL + DOL;
    });
  }
  function splitEqualChain(src) {
    var depth = 0, cuts = [];
    for (var i = 0; i < src.length; i++) {
      var ch = src.charAt(i);
      if (ch === BS) {
        var name = (/^[A-Za-z]+/.exec(src.slice(i + 1)) || [""])[0];
        if (name === "left") depth++;
        else if (name === "right") depth = Math.max(0, depth - 1);
        else if (name === "quad" || name === "qquad" || name === "text") return "";
        i += name ? name.length : 1;
        continue;
      }
      if (ch === "{") depth++;
      else if (ch === "}") depth = Math.max(0, depth - 1);
      else if (depth === 0 && (ch === "," || ch === ";")) return "";
      else if (depth === 0 && ch === "=") cuts.push(i);
    }
    if (cuts.length < 2) return "";
    var parts = [], start = 0;
    for (var k = 0; k < cuts.length; k++) {
      parts.push(src.slice(start, cuts[k]).trim());
      start = cuts[k] + 1;
    }
    parts.push(src.slice(start).trim());
    for (var p = 0; p < parts.length; p++) {
      if (!parts[p]) return "";
    }
    var out = parts[0] + " &= " + parts[1];
    for (var j = 2; j < parts.length; j++) out += " " + BS + BS + " &= " + parts[j];
    return BS + "begin{aligned}" + out + BS + "end{aligned}";
  }
  function renderMath(md) {
    var idx = 0;
    var blocks = [];
    function protect(latex, display) {
      var src = String(latex || "").replace(/\r/g, "");
      var multi = isMultiLineLatex(src);
      if (!multi) src = src.replace(/[ \t]*\n[ \t]*/g, " ").replace(/[ \t]{2,}/g, " ");
      src = src.trim();
      if (!src) return "";
      if (!multi) {
        var chain = splitEqualChain(src);
        if (chain) { src = chain; multi = true; display = true; }
      }
      if (!display && src.indexOf(BS + "displaystyle") < 0 && /\\(?:lim|sum|prod|int|iint|oint|frac)(?![A-Za-z])/.test(src)) {
        src = BS + "displaystyle " + src;
      }
      var memoKey = (display ? "1" : "0") + (multi ? "m" : "s") + "\n" + src;
      var html = katexMemo[memoKey];
      if (!html) {
        var drawn = "";
        try {
          if (window.katex && typeof katex.renderToString === "function") {
            drawn = katex.renderToString(src, { displayMode: !!display, throwOnError: false, strict: "ignore" });
          }
        } catch (e) { drawn = ""; }
        if (!drawn || drawn.indexOf("katex-error") >= 0) {
          html = "<span class=\"math-plain\">" + escapeHtml(src) + "</span>";
        } else if (display) {
          var cls = multi ? "math-scroll multi" : "math-scroll single";
          html = "<div class=\"math-wrap\"><div class=\"" + cls + "\">" + drawn + "</div></div>";
        } else {
          html = drawn;
        }
        katexMemo[memoKey] = html;
      }
      var key = "@@KATEX" + (idx++) + "@@";
      blocks.push({ key: key, html: html });
      return key;
    }
    md = wrapBareEnvs(String(md || ""));
    md = md.split(BS + DOL).join(DOL);
    md = md.replace(/\\\\(?=[a-zA-Z])/g, "\\");
    md = md.replace(/\\\[([\s\S]*?)\\\]/g, function (_, p1) { return protect(p1, true); });
    md = md.replace(/\\\(([\s\S]*?)\\\)/g, function (_, p1) { return protect(p1, false); });
    var drawn = "", cursor = 0;
    while (cursor < md.length) {
      if (md.charAt(cursor) === DOL && md.charAt(cursor + 1) === DOL) {
        var endDisplay = md.indexOf(DOL + DOL, cursor + 2);
        if (endDisplay < 0) { drawn += md.slice(cursor); break; }
        drawn += protect(md.slice(cursor + 2, endDisplay), true);
        cursor = endDisplay + 2;
        continue;
      }
      if (md.charAt(cursor) === DOL) {
        var endInline = md.indexOf(DOL, cursor + 1);
        if (endInline < 0) { drawn += md.slice(cursor); break; }
        drawn += protect(md.slice(cursor + 1, endInline), false);
        cursor = endInline + 1;
        continue;
      }
      drawn += md.charAt(cursor);
      cursor += 1;
    }
    md = drawn.replace(/\n{3,}/g, "\n\n");
    var html = parseMarkdown(md || "");
    blocks.forEach(function (b) { html = html.split(b.key).join(b.html); });
    return html;
  }
  function reportHeight() {
    var el = document.getElementById("content");
    if (!el) return 0;
    var root = el.getBoundingClientRect();
    var bottom = root.top;
    var kids = el.children;
    for (var i = 0; i < kids.length; i++) {
      var box = kids[i].getBoundingClientRect();
      if (box.bottom > bottom) bottom = box.bottom;
      var extras = kids[i].querySelectorAll(".katex, .katex-display, .math-scroll, img");
      for (var j = 0; j < extras.length; j++) {
        var extra = extras[j].getBoundingClientRect();
        if (extra.bottom > bottom) bottom = extra.bottom;
      }
    }
    return Math.ceil(Math.max(el.scrollHeight || 0, document.body.scrollHeight || 0, bottom - root.top) + 4);
  }
  window.setQaHtml = function (html) {
    var root = document.getElementById("content");
    if (!root) return 0;
    root.innerHTML = html || "";
    return reportHeight();
  };
  window.setQaContent = function (md, streaming, answerLayout) {
    var root = document.getElementById("content");
    if (!root) return 0;
    try {
      var masked = streaming ? maskUnclosed(md || "") : { body: String(md || ""), tail: "" };
      root.innerHTML = renderMath(masked.body);
      if (masked.tail) {
        var tail = document.createElement("span");
        tail.className = "math-plain";
        tail.textContent = masked.tail;
        root.appendChild(tail);
      }
    } catch (e) {
      root.innerHTML = fallbackMarkdown(String(md || ""));
    }
    if (streaming) {
      var cursor = document.createElement("span");
      cursor.className = "cursor";
      cursor.textContent = "◊";
      root.appendChild(cursor);
    }
    paintedMd = String(md || "");
    return reportHeight();
  };
})();
