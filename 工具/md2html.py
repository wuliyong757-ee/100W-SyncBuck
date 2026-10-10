# -*- coding: utf-8 -*-
"""把一份 markdown 转成「自包含」的 HTML —— 图片转 base64 嵌进文件里，
生成一个 .html 就能带走，发给手机/平板直接打开，不依赖任何外部文件。

用法:  python md2html.py <输入.md> <输出.html>

渲染器部分复用聊天记录查看器（C:\\Users\\吴立勇\\聊天记录\\build.py）里那套
手写的 markdown 渲染，针对「给人看的文档」做了四处调整：
  1. 图片 ![]() 转 base64 内嵌，并支持点击放大（原理图很宽）
  2. 标题按真实层级（# -> h1），不是聊天记录那种从 h3 起
  3. 引用块里的空行分段（原来的版本会把整段引用压成一行）
  4. 表格外面套一层可横向滚动的容器（手机上表格不撑破屏）
"""
import base64
import html
import mimetypes
import os
import re
import sys

_CTRL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")


def esc(s):
    return html.escape(_CTRL.sub("", str(s)))


# ---------------------------------------------------------------- 行内

def _img(m, base):
    alt, src = m.group(1), m.group(2).strip()
    path = os.path.join(base, src)
    try:
        with open(path, "rb") as f:
            data = base64.b64encode(f.read()).decode("ascii")
    except OSError:
        return '<span class="missing">[图片没找到: %s]</span>' % src
    mime = mimetypes.guess_type(src)[0] or "image/png"
    return ('<span class="figwrap"><img class="fig" src="data:%s;base64,%s"'
            ' alt="%s" title="点一下放大 / 再点一下缩回"></span>'
            % (mime, data, alt))


def _link(m):
    """文档之间的互链：xxx.md -> xxx.html，这样一整套转出来还能点着跳"""
    txt, tgt = m.group(1), m.group(2)
    if tgt.endswith(".md"):
        tgt = tgt[:-3] + ".html"
    elif ".md#" in tgt:
        tgt = tgt.replace(".md#", ".html#")
    return '<a href="%s">%s</a>' % (tgt, txt)


def _inline(s, base="."):
    """行内标记。输入必须已经 html.escape 过。"""
    s = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", lambda m: _img(m, base), s)
    s = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", _link, s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<em>\1</em>", s)
    return s


def _cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def _block_start(lines, i):
    s = lines[i].strip()
    if not s:
        return True
    if s.startswith("```") or s.startswith("|") or s.startswith("&gt;"):
        return True
    if re.match(r"^#{1,6}\s+", s):
        return True
    if re.match(r"^([-*+]|\d+\.)\s+", s):
        return True
    if re.match(r"^(-{3,}|\*{3,}|_{3,})$", s):
        return True
    return False


def _slug(text, used):
    """给标题生成一个稳定 id（中文标题也照收，浏览器认）"""
    s = re.sub(r"<[^>]+>", "", text)
    s = re.sub(r"[^\w\u4e00-\u9fff]+", "-", s).strip("-")
    s = s or "h"
    n, base = 1, s
    while s in used:
        n += 1
        s = "%s-%d" % (base, n)
    used.add(s)
    return s


# ---------------------------------------------------------------- 块级

def md(text, base="."):
    lines = text.split("\n")
    out = []
    used = set()
    i, n = 0, len(lines)

    while i < n:
        s = lines[i].strip()

        if s.startswith("```"):                              # 围栏代码块
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            out.append("<pre>%s</pre>" % "\n".join(buf))
            continue

        if (s.startswith("|") and i + 1 < n                 # 表格
                and re.match(r"^\|[\s:|-]+\|$", lines[i + 1].strip())):
            head = _cells(s)
            i += 2
            body = []
            while i < n and lines[i].strip().startswith("|"):
                body.append(_cells(lines[i].strip()))
                i += 1
            t = ["<div class='tw'><table><thead><tr>"]
            t += ["<th>%s</th>" % _inline(c, base) for c in head]
            t.append("</tr></thead><tbody>")
            for r in body:
                t.append("<tr>" + "".join("<td>%s</td>" % _inline(c, base)
                                          for c in r) + "</tr>")
            t.append("</tbody></table></div>")
            out.append("".join(t))
            continue

        m = re.match(r"^(#{1,6})\s+(.*)$", s)               # 标题
        if m:
            lv = min(len(m.group(1)), 6)
            body = _inline(m.group(2), base)
            out.append('<h%d id="%s">%s</h%d>'
                       % (lv, _slug(m.group(2), used), body, lv))
            i += 1
            continue

        if re.match(r"^(-{3,}|\*{3,}|_{3,})$", s):          # 分隔线
            out.append("<hr>")
            i += 1
            continue

        if s.startswith("&gt;"):                            # 引用
            buf = []
            while i < n:
                cur = lines[i].strip()
                if cur.startswith("&gt;"):
                    buf.append(re.sub(r"^&gt;\s?", "", cur))
                    i += 1
                elif (not cur and i + 1 < n
                      and lines[i + 1].strip().startswith("&gt;")):
                    buf.append("")                          # 引用内的空行 = 分段
                    i += 1
                else:
                    break
            paras = []
            for chunk in "\n".join(buf).split("\n\n"):
                chunk = "".join(x for x in chunk.split("\n") if x.strip())
                if chunk.strip():
                    paras.append("<p>%s</p>" % _inline(chunk, base))
            out.append("<blockquote>%s</blockquote>" % "".join(paras))
            continue

        if re.match(r"^([-*+]|\d+\.)\s+", s):               # 列表
            ordered = bool(re.match(r"^\d+\.\s+", s))
            buf = []
            while i < n and re.match(r"^([-*+]|\d+\.)\s+", lines[i].strip()):
                buf.append(re.sub(r"^([-*+]|\d+\.)\s+", "", lines[i].strip()))
                i += 1
            tag = "ol" if ordered else "ul"
            out.append("<%s>%s</%s>" % (
                tag, "".join("<li>%s</li>" % _inline(b, base) for b in buf), tag))
            continue

        if not s:                                            # 空行
            i += 1
            continue

        buf = []                                             # 普通段落
        while i < n and not _block_start(lines, i):
            if lines[i].strip():
                buf.append(lines[i].strip())
            i += 1
        out.append("<p>%s</p>" % _inline("".join(buf), base))

    return "\n".join(out)


# ---------------------------------------------------------------- 模板

CSS = """
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;padding:0;background:#f5f6f8;color:#1f2328;
 font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Hiragino Sans GB",
 "Microsoft YaHei","Source Han Sans SC",sans-serif;
 font-size:17px;line-height:1.78;word-wrap:break-word}
.wrap{max-width:840px;margin:0 auto;background:#fff;padding:20px 20px 72px;
 min-height:100vh;box-shadow:0 0 24px rgba(0,0,0,.06)}
h1{font-size:25px;line-height:1.4;margin:8px 0 6px;color:#12355c;
 border-bottom:3px solid #12355c;padding-bottom:12px}
h2{font-size:21px;margin:40px 0 12px;color:#12355c;padding-left:11px;
 border-left:5px solid #2a4d8f}
h3{font-size:18px;margin:28px 0 8px;color:#1b3c6b}
h4{font-size:17px;margin:22px 0 6px;color:#1b3c6b}
p{margin:11px 0}
strong{color:#0d2b52}
a{color:#1a5fb4}
hr{border:none;border-top:1px solid #e2e4e8;margin:30px 0}
code{background:#f0f2f5;border-radius:4px;padding:2px 5px;font-size:.88em;
 font-family:ui-monospace,Consolas,"Courier New",monospace;color:#a4362c;
 word-break:break-word}
pre{background:#f6f8fa;border:1px solid #e2e4e8;border-radius:8px;
 padding:12px 14px;overflow-x:auto;font-size:14px;line-height:1.62;
 font-family:ui-monospace,Consolas,"Courier New",monospace}
pre code{background:none;padding:0;color:#1f2328;font-size:14px}
blockquote{margin:14px 0;padding:10px 16px;background:#fbfaf5;
 border-left:4px solid #d8b24a;border-radius:0 8px 8px 0}
blockquote p{margin:7px 0}
blockquote p:first-child{margin-top:0}
blockquote p:last-child{margin-bottom:0}
ul,ol{margin:11px 0;padding-left:24px}
li{margin:5px 0}
.tw{overflow-x:auto;-webkit-overflow-scrolling:touch;margin:14px 0}
table{border-collapse:collapse;width:100%;font-size:15px;min-width:340px}
th,td{border:1px solid #dfe3e8;padding:7px 10px;text-align:left;
 vertical-align:top}
th{background:#eef4ff;color:#12355c;font-weight:600;white-space:nowrap}
tbody tr:nth-child(even){background:#fafbfc}
.figwrap{display:block;overflow-x:auto;-webkit-overflow-scrolling:touch;margin:18px 0}
img.fig{display:block;width:100%;height:auto;border:1px solid #d7dbe0;
 border-radius:8px;cursor:zoom-in}
img.fig.zoom{width:1780px;max-width:none;cursor:zoom-out}
#top{position:fixed;right:16px;bottom:18px;width:46px;height:46px;
 border-radius:50%;background:#12355c;color:#fff;border:none;font-size:20px;
 box-shadow:0 3px 12px rgba(0,0,0,.28);cursor:pointer;display:none;
 align-items:center;justify-content:center;padding:0}
#top.on{display:flex}
.missing{color:#c0392b;background:#fdecec;padding:6px 10px;border-radius:6px;
 display:inline-block}
.nav{margin:2px 0 16px}
.nav a{display:inline-block;background:#eef4ff;border:1px solid #cddcf5;color:#1a5fb4;
 text-decoration:none;padding:7px 14px;border-radius:8px;font-size:15px}
.grp{margin:30px 0 10px;font-size:19px;font-weight:600;color:#12355c;
 padding-left:11px;border-left:5px solid #2a4d8f}
.card{display:block;text-decoration:none;color:inherit;background:#fff;
 border:1px solid #e2e8f2;border-radius:10px;padding:12px 16px;margin:10px 0}
.card:active,.card:hover{border-color:#9db8e0;background:#f8fbff}
.card b{color:#12355c;font-size:17px;display:block;margin-bottom:3px}
.card span{color:#6a7280;font-size:14px;line-height:1.5}
.toc{background:#f7f9fc;border:1px solid #dce3ee;border-radius:10px;
 padding:12px 18px;margin:20px 0 8px}
.toc b{color:#12355c;display:block;margin-bottom:6px;font-size:15px}
.toc ol{margin:0;padding-left:22px;font-size:16px}
.toc li{margin:4px 0}
.toc a{text-decoration:none}
footer{margin-top:44px;padding-top:16px;border-top:1px solid #e2e4e8;
 color:#8a9099;font-size:13px}
@media(max-width:520px){
 .wrap{padding:14px 13px 60px}
 body{font-size:16px}
 h1{font-size:21px} h2{font-size:19px} h3{font-size:17px}
 table{font-size:14px}
}
"""

JS = """
document.querySelectorAll('img.fig').forEach(function(im){
  im.addEventListener('click', function(){
    im.classList.toggle('zoom');
    if (im.classList.contains('zoom')) {
      im.parentElement.scrollLeft = (1780 - window.innerWidth) / 2;
    }
  });
});
var bt = document.getElementById('top');
addEventListener('scroll', function(){
  bt.classList.toggle('on', window.scrollY > 600);
});
bt.addEventListener('click', function(){ scrollTo({top:0, behavior:'smooth'}); });
"""


def build(src, dst, nav=""):
    with open(src, "r", encoding="utf-8") as f:
        raw = f.read()
    base = os.path.dirname(os.path.abspath(src))

    m = re.search(r"^#\s+(.*)$", raw, re.M)
    title = html.escape(m.group(1).strip()) if m else os.path.basename(src)

    # 目录：拿 h2（## 那一级）
    toc, k = [], 0
    for sec in re.findall(r"^##\s+(.*)$", raw, re.M):
        k += 1
        toc.append('<li><a href="#__toc_%d">%s</a></li>'
                   % (k, _inline(esc(sec.strip()), base)))
    toc_html = ("<nav class='toc'><b>目录（点一条跳过去）</b><ol>%s</ol></nav>"
                % "".join(toc)) if toc else ""

    body = md(esc(raw), base)

    # 把 h2 的真实 id 对回目录锚点
    k = 0
    def _fix(mm):
        nonlocal k
        k += 1
        return '<h2 id="__toc_%d">' % k
    body = re.sub(r"<h2\s+id=\"[^\"]*\">", _fix, body)

    # 目录插在第一个 h2 之前 —— 也就是标题、引言、图之后，正文之前
    if toc_html:
        body = body.replace('<h2 id="__toc_1">',
                            toc_html + '\n<h2 id="__toc_1">', 1)

    doc = ("<!DOCTYPE html>\n<html lang='zh-CN'>\n<head>\n"
           "<meta charset='utf-8'>\n"
           "<meta name='viewport' content='width=device-width,initial-scale=1'>\n"
           "<title>%s</title>\n<style>%s</style>\n</head>\n<body>\n"
           "<div class='wrap'>\n%s%s\n"
           "<footer>生成自 %s　·　图片已嵌在本文件里，可以单独发走</footer>\n"
           "</div>\n<button id='top' title='回到顶部'>↑</button>\n"
           "<script>%s</script>\n</body>\n</html>\n"
           % (title, CSS, nav, body,
              html.escape(os.path.basename(src)), JS))

    with open(dst, "w", encoding="utf-8") as f:
        f.write(doc)
    return len(doc)


def _first_heading(path):
    """拿文档的第一个 # 标题当卡片标题；再摘一句正文当简介。

    简介要挑「像人话」的那一行：跳过标题/引用/表格/列表/代码/图片，
    并且要求中文够多（这样公式行、代码行会被自动跳过），
    再在句号处断开——截在半句上比不写还难看。
    """
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.read().split("\n")
    except OSError:
        return None, ""

    title, blurb = None, ""
    for ln in lines:
        s = ln.strip()
        if title is None:
            if s.startswith("# ") and not s.startswith("##"):
                title = s[2:].strip()
            continue
        if blurb or not s:
            continue
        if s[0] in "#>|-*!`=（(" or re.match(r"^\d+\.\s", s):
            continue
        if len(re.findall(r"[一-鿿]", s)) < 8:
            continue
        t = re.sub(r"!?\[[^\]]*\]\([^)]*\)", "", s)      # 去掉图/链接
        t = re.sub(r"\s+", " ", re.sub(r"[*`]", "", t)).strip()
        if len(re.findall(r"[一-鿿]", t)) < 8:
            continue
        if t.endswith(("：", ":")):                      # 引导句，本身就干净
            blurb = t
            continue
        j = t.find("。")
        if 16 <= j <= 110:
            blurb = t[:j + 1]
        else:
            k = max(t.rfind("，", 0, 88), t.rfind("、", 0, 88),
                    t.rfind("；", 0, 88))
            blurb = t[:k + 1] if k >= 20 else t[:88]
    return title, blurb


def build_index(outdir, groups, srcdir):
    secs = []
    for name, files in groups:
        cards = []
        for fn in files:
            src = os.path.join(srcdir, fn)
            if not os.path.exists(src):
                continue
            t, b = _first_heading(src)
            cards.append(
                "<a class='card' href='%s.html'><b>%s</b><span>%s</span></a>"
                % (fn[:-3], html.escape(t or fn), html.escape(b)))
        if cards:
            secs.append("<div class='grp'>%s</div>%s"
                        % (html.escape(name), "".join(cards)))

    doc = ("<!DOCTYPE html>\n<html lang='zh-CN'>\n<head>\n"
           "<meta charset='utf-8'>\n"
           "<meta name='viewport' content='width=device-width,initial-scale=1'>\n"
           "<title>100W 同步 Buck · 学习包</title>\n<style>%s</style>\n</head>\n"
           "<body>\n<div class='wrap'>\n"
           "<h1>100W 同步 Buck · 学习包</h1>\n"
           "<p>48 V → 12 V / 8 A，LM5146 电压模式 + 输入前馈，Type III 补偿，300 kHz。"
           "这一整套是设计文档＋仿真＋串讲，按顺序看就行。</p>\n"
           "<p>从 <b>总览</b> 或 <b>11-串讲</b> 开始最省事："
           "串讲是按电流走的顺序把七环串成一条线，卡在哪一环再点进那一份细看。</p>\n"
           "%s\n"
           "<footer>实物未打板 —— 这是设计包，不是实测报告。</footer>\n"
           "</div>\n<button id='top' title='回到顶部'>↑</button>\n"
           "<script>%s</script>\n</body>\n</html>\n"
           % (CSS, "".join(secs), JS))

    dst = os.path.join(outdir, "index.html")
    with open(dst, "w", encoding="utf-8") as f:
        f.write(doc)
    return len(doc)


STUDY_GROUPS = [
    ("先看这两份", ["总览.md", "11-串讲.md"]),
    ("七环详解（按顺序）", [
        "01-拓扑与器件应力.md", "02-电感设计.md", "03-电容设计.md",
        "04-开关管与驱动.md", "05-控制模式与电流采样.md",
        "06-环路补偿.md", "07-保护设计.md"]),
    ("热设计与原理图 / BOM", [
        "08-热设计.md", "09-原理图与BOM.md", "BOM-说明.md"]),
    ("面试弹药", ["10-面试速答卡.md"]),
    ("项目说明与索引", ["README.md", "00-设计大纲与进度.md"]),
    ("附录（备查，先别看）", ["10-原理图绘制顺序.md", "11-符号引脚布局.md"]),
]


def build_site(srcdir, outdir):
    if not os.path.isdir(outdir):
        os.makedirs(outdir)
    nav = "<div class='nav'><a href='index.html'>← 回到目录</a></div>"

    done, files = 0, []
    for _, group in STUDY_GROUPS:
        files += group
    for fn in files:
        src = os.path.join(srcdir, fn)
        if not os.path.exists(src):
            print("skip (not found): %s" % fn)
            continue
        dst = os.path.join(outdir, fn[:-3] + ".html")
        build(src, dst, nav=nav)
        done += 1
        print("  ok  %s" % (fn[:-3] + ".html"))

    build_index(outdir, STUDY_GROUPS, srcdir)
    print("  ok  index.html")
    return done + 1


def make_zip(folder):
    """把整包压成一个 zip —— 平板那边解压一下、点 index.html 就能看。
    走 Python 自带的 zipfile，省得在 .cmd 里写中文路径。"""
    import shutil
    base = folder.rstrip("/\\")
    out = shutil.make_archive(base, "zip", os.path.dirname(base),
                              os.path.basename(base))
    return out


if __name__ == "__main__":
    # 输出被重定向（管道/文件）时 Python 会用系统区域编码，中文会直接抛
    # UnicodeEncodeError；控制台下不受影响（走 WriteConsoleW，中文正常）
    try:
        sys.stdout.reconfigure(errors="replace")
    except Exception:
        pass

    if sys.argv[1:2] == ["--bundle"]:
        # 输出目录可以省略：默认 = 桌面\开关电源学习包。
        # 故意留成「省略」这个形式，是为了让调用它的 .cmd 里一个中文字都没有
        # —— 批处理里的中文会被控制台代码页读花，生成一个乱码名字的文件夹。
        if len(sys.argv) == 4:
            outdir = sys.argv[3]
        elif len(sys.argv) == 3:
            outdir = os.path.join(os.path.expanduser("~"), "Desktop",
                                  "开关电源学习包")
        else:
            print("usage: python md2html.py --bundle <项目目录> [<输出目录>]")
            sys.exit(2)
        n = build_site(sys.argv[2], outdir)
        z = make_zip(outdir)
        # 这几行故意用中文：Windows 控制台下 Python 走 WriteConsoleW，
        # 中文能正常显示（.cmd 里写中文才会被代码页吃掉）
        print("")
        print("完成：%d 个页面" % n)
        print("  文件夹  %s" % outdir)
        print("  压缩包  %s" % z)
        print("传到平板就发那个 .zip，解压后先点 index.html")
        sys.exit(0)

    if sys.argv[1:2] == ["--site"]:
        if len(sys.argv) != 4:
            print("usage: python md2html.py --site <项目目录> <输出目录>")
            sys.exit(2)
        n = build_site(sys.argv[2], sys.argv[3])
        print("done: %d files" % n)
        sys.exit(0)

    if len(sys.argv) == 3:
        src, dst = sys.argv[1], sys.argv[2]
    elif len(sys.argv) == 1:
        # 不带参数 = 默认活儿：项目里的 11-串讲.md -> 桌面 11-串讲.html
        here = os.path.dirname(os.path.abspath(__file__))
        src = os.path.join(here, "..", "11-串讲.md")
        dst = os.path.join(os.path.expanduser("~"), "Desktop", "11-串讲.html")
    else:
        print("usage: python md2html.py [<in.md> <out.html>]")
        print("       python md2html.py --site <项目目录> <输出目录>")
        sys.exit(2)

    for p in (src, os.path.dirname(os.path.abspath(dst))):
        if not os.path.exists(p):
            print("NOT FOUND: %s" % p)
            sys.exit(1)

    size = build(src, dst)
    print("ok: %s (%d bytes)" % (dst, size))
