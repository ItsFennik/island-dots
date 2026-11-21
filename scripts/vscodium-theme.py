#!/usr/bin/env python3
"""Island palette -> VSCodium colour theme.

  vscodium-theme.py <themes/id.json> [extensions-dir]

Writes a tiny local extension (island.island-theme) into ~/.vscode-oss/extensions and registers it
in extensions.json. The theme is contributed with "_watch": true, so VSCodium repaints live when
this script rewrites the theme file (no reload). Everything sits on one background with no borders;
the accent is only used for focus, cursor, badges and the active line number.
"""
import json, os, sys, time

pal = json.load(open(sys.argv[1]))
ext_root = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.vscode-oss/extensions")
EXT_ID, VER = "island.island-theme", "1.0.0"
ext_dir = os.path.join(ext_root, f"{EXT_ID}-{VER}")
os.makedirs(os.path.join(ext_dir, "themes"), exist_ok=True)

p = pal.get
dark = bool(p("dark", True))
bg, bg_alt, surface, overlay = p("bg"), p("bg_alt"), p("surface"), p("overlay")
fg, dim, faint = p("fg"), p("fg_dim"), p("fg_faint")
acc, acc_fg = p("accent"), p("accent_fg")
red, green, yellow, blue, magenta, cyan = (p(k) for k in ("red", "green", "yellow", "blue", "magenta", "cyan"))
a = lambda c, x: c + x          # "#rrggbb" + "aa"
none = "#00000000"

colors = {
    # base
    "foreground": fg, "descriptionForeground": dim, "disabledForeground": faint,
    "errorForeground": red, "icon.foreground": dim, "focusBorder": none,
    "contrastBorder": none, "contrastActiveBorder": none, "widget.border": none, "widget.shadow": a("#000000", "40"),
    "selection.background": a(acc, "40"), "textLink.foreground": acc, "textLink.activeForeground": acc,
    "sash.hoverBorder": a(acc, "80"), "scrollbar.shadow": none,
    "scrollbarSlider.background": a(fg, "14"), "scrollbarSlider.hoverBackground": a(fg, "26"),
    "scrollbarSlider.activeBackground": a(fg, "33"),
    "progressBar.background": acc, "badge.background": acc, "badge.foreground": acc_fg,
    # window chrome: one flat surface everywhere
    "titleBar.activeBackground": bg, "titleBar.inactiveBackground": bg, "titleBar.border": none,
    "titleBar.activeForeground": dim, "titleBar.inactiveForeground": faint,
    "menubar.selectionBackground": a(fg, "14"), "menu.background": surface, "menu.foreground": fg,
    "menu.selectionBackground": a(acc, "33"), "menu.selectionForeground": fg, "menu.separatorBackground": overlay,
    "menu.border": none,
    "activityBar.background": bg, "activityBar.foreground": fg, "activityBar.inactiveForeground": faint,
    "activityBar.border": none, "activityBar.activeBorder": acc, "activityBarBadge.background": acc,
    "activityBarBadge.foreground": acc_fg,
    "sideBar.background": bg, "sideBar.foreground": dim, "sideBar.border": none,
    "sideBarTitle.foreground": faint, "sideBarSectionHeader.background": bg,
    "sideBarSectionHeader.foreground": faint, "sideBarSectionHeader.border": none,
    "statusBar.background": bg, "statusBar.foreground": faint, "statusBar.border": none,
    "statusBar.noFolderBackground": bg, "statusBar.debuggingBackground": bg, "statusBar.debuggingForeground": yellow,
    "statusBarItem.hoverBackground": a(fg, "14"), "statusBarItem.remoteBackground": bg,
    "statusBarItem.remoteForeground": acc,
    "panel.background": bg, "panel.border": none, "panelTitle.activeForeground": fg,
    "panelTitle.inactiveForeground": faint, "panelTitle.activeBorder": acc, "panelSection.border": none,
    # tabs
    "editorGroupHeader.tabsBackground": bg, "editorGroupHeader.noTabsBackground": bg,
    "editorGroupHeader.tabsBorder": none, "editorGroupHeader.border": none, "editorGroup.border": a(overlay, "80"),
    "editorGroup.emptyBackground": bg, "breadcrumb.background": bg,
    "tab.activeBackground": bg, "tab.inactiveBackground": bg, "tab.activeForeground": fg,
    "tab.inactiveForeground": faint, "tab.border": none, "tab.activeBorder": none, "tab.activeBorderTop": none,
    "tab.unfocusedActiveForeground": dim, "tab.hoverBackground": bg, "tab.lastPinnedBorder": none,
    # lists / trees
    "list.activeSelectionBackground": a(acc, "26"), "list.activeSelectionForeground": fg,
    "list.inactiveSelectionBackground": a(fg, "0f"), "list.inactiveSelectionForeground": fg,
    "list.hoverBackground": a(fg, "0a"), "list.hoverForeground": fg, "list.focusOutline": none,
    "list.focusBackground": a(acc, "1a"), "list.highlightForeground": acc, "list.errorForeground": red,
    "list.warningForeground": yellow, "tree.indentGuidesStroke": a(overlay, "80"),
    "gitDecoration.modifiedResourceForeground": yellow, "gitDecoration.addedResourceForeground": green,
    "gitDecoration.untrackedResourceForeground": green, "gitDecoration.deletedResourceForeground": red,
    "gitDecoration.ignoredResourceForeground": faint, "gitDecoration.conflictingResourceForeground": magenta,
    # inputs / widgets
    "input.background": surface, "input.foreground": fg, "input.border": none,
    "input.placeholderForeground": faint, "inputOption.activeBorder": none,
    "inputOption.activeBackground": a(acc, "33"), "inputValidation.errorBorder": red,
    "dropdown.background": surface, "dropdown.border": none, "dropdown.foreground": fg,
    "button.background": acc, "button.foreground": acc_fg, "button.hoverBackground": a(acc, "d9"),
    "button.secondaryBackground": surface, "button.secondaryForeground": fg, "button.border": none,
    "checkbox.background": surface, "checkbox.border": none,
    "quickInput.background": surface, "quickInput.foreground": fg, "quickInputTitle.background": surface,
    "quickInputList.focusBackground": a(acc, "26"), "pickerGroup.border": none, "pickerGroup.foreground": acc,
    "keybindingLabel.background": bg, "keybindingLabel.border": none, "keybindingLabel.bottomBorder": none,
    "keybindingLabel.foreground": dim,
    "notifications.background": surface, "notifications.border": none, "notificationCenter.border": none,
    "notificationCenterHeader.background": surface, "notificationToast.border": none,
    "editorWidget.background": surface, "editorWidget.border": none, "editorWidget.foreground": fg,
    "editorSuggestWidget.background": surface, "editorSuggestWidget.border": none,
    "editorSuggestWidget.selectedBackground": a(acc, "26"), "editorSuggestWidget.highlightForeground": acc,
    "editorHoverWidget.background": surface, "editorHoverWidget.border": none,
    "peekView.border": none, "peekViewEditor.background": bg_alt, "peekViewResult.background": surface,
    "peekViewTitle.background": surface,
    "debugToolBar.background": surface, "debugToolBar.border": none,
    # editor
    "editor.background": bg, "editor.foreground": fg,
    "editorLineNumber.foreground": a(faint, "80"), "editorLineNumber.activeForeground": acc,
    "editorCursor.foreground": acc, "editor.selectionBackground": a(acc, "33"),
    "editor.inactiveSelectionBackground": a(acc, "1a"), "editor.selectionHighlightBackground": a(acc, "1a"),
    "editor.wordHighlightBackground": a(fg, "14"), "editor.wordHighlightStrongBackground": a(fg, "1f"),
    "editor.findMatchBackground": a(yellow, "4d"), "editor.findMatchHighlightBackground": a(yellow, "26"),
    "editor.lineHighlightBackground": none, "editor.lineHighlightBorder": none,
    "editorIndentGuide.background1": a(overlay, "40"), "editorIndentGuide.activeBackground1": a(overlay, "a0"),
    "editorWhitespace.foreground": a(faint, "40"), "editorRuler.foreground": a(overlay, "60"),
    "editorBracketMatch.background": a(acc, "26"), "editorBracketMatch.border": none,
    "editorGutter.background": bg, "editorGutter.modifiedBackground": a(yellow, "a0"),
    "editorGutter.addedBackground": a(green, "a0"), "editorGutter.deletedBackground": a(red, "a0"),
    "editorOverviewRuler.border": none, "editorError.foreground": red, "editorWarning.foreground": yellow,
    "editorInfo.foreground": blue, "editorHint.foreground": cyan,
    "editorStickyScroll.background": bg, "editorStickyScrollHover.background": surface,
    "editorBracketHighlight.foreground1": blue, "editorBracketHighlight.foreground2": magenta,
    "editorBracketHighlight.foreground3": cyan, "editorBracketHighlight.foreground4": yellow,
    "editorBracketHighlight.foreground5": green, "editorBracketHighlight.foreground6": red,
    "diffEditor.insertedTextBackground": a(green, "26"), "diffEditor.removedTextBackground": a(red, "26"),
    "diffEditor.border": none, "minimap.background": bg,
    # terminal
    "terminal.background": bg, "terminal.foreground": fg, "terminalCursor.foreground": acc,
    "terminal.selectionBackground": a(acc, "40"), "terminal.border": none,
    **{f"terminal.ansi{n}": c for n, c in (("Black", surface), ("Red", red), ("Green", green), ("Yellow", yellow),
       ("Blue", blue), ("Magenta", magenta), ("Cyan", cyan), ("White", dim))},
    **{f"terminal.ansiBright{n}": c for n, c in (("Black", overlay), ("Red", red), ("Green", green),
       ("Yellow", yellow), ("Blue", blue), ("Magenta", magenta), ("Cyan", cyan), ("White", fg))},
    "welcomePage.background": bg, "walkThrough.embeddedEditorBackground": bg_alt,
}

def tok(scope, fgc, style=None):
    s = {"foreground": fgc}
    if style: s["fontStyle"] = style
    return {"scope": scope, "settings": s}

token_colors = [
    {"settings": {"foreground": fg, "background": bg}},
    tok(["comment", "punctuation.definition.comment", "string.comment"], faint, "italic"),
    tok(["keyword", "storage.type", "storage.modifier", "keyword.control", "keyword.operator.new",
         "keyword.operator.expression", "keyword.operator.logical.python"], magenta),
    tok(["keyword.operator", "punctuation", "meta.brace", "punctuation.separator", "punctuation.terminator"], dim),
    tok(["string", "string.quoted", "string.template", "markup.inline.raw"], green),
    tok(["constant.character.escape", "string.regexp", "constant.other.placeholder"], cyan),
    tok(["constant.numeric", "constant.language", "constant.other", "support.constant",
         "variable.other.constant", "variable.other.enummember"], yellow),
    tok(["entity.name.function", "support.function", "meta.function-call.generic", "variable.function"], blue),
    tok(["entity.name.type", "entity.name.class", "support.type", "support.class", "entity.other.inherited-class",
         "storage.type.primitive", "entity.name.namespace"], yellow),
    tok(["variable", "meta.definition.variable", "variable.other.readwrite"], fg),
    tok(["variable.parameter", "meta.parameter"], fg, "italic"),
    tok(["variable.language", "variable.language.this", "variable.language.self"], red, "italic"),
    tok(["entity.name.tag", "meta.tag.sgml"], red),
    tok(["entity.other.attribute-name", "support.type.property-name", "meta.object-literal.key"], cyan),
    tok(["entity.name.function.decorator", "meta.decorator", "punctuation.decorator", "entity.name.label"], cyan),
    tok(["markup.heading", "entity.name.section"], acc, "bold"),
    tok(["markup.bold"], fg, "bold"), tok(["markup.italic"], fg, "italic"),
    tok(["markup.underline.link", "string.other.link"], blue),
    tok(["markup.inserted"], green), tok(["markup.deleted"], red), tok(["markup.changed"], yellow),
    tok(["invalid", "invalid.illegal"], red),
]

theme = {
    "name": "Island", "type": "dark" if dark else "light", "semanticHighlighting": True,
    "colors": colors, "tokenColors": token_colors,
    "semanticTokenColors": {"parameter": {"foreground": fg, "italic": True}, "variable.readonly": yellow,
                            "property": fg, "namespace": yellow, "enumMember": yellow, "macro": cyan,
                            "selfKeyword": {"foreground": red, "italic": True}},
}

pkg = {
    "name": "island-theme", "displayName": "Island", "publisher": "island", "version": VER,
    "description": "Generated by quickshell/island (scripts/vscodium-theme.py). Change the theme in Island.",
    "engines": {"vscode": "^1.60.0"}, "categories": ["Themes"],
    "contributes": {"themes": [{"id": "Island", "label": "Island", "uiTheme": "vs-dark" if dark else "vs",
                                "path": "./themes/island-color-theme.json", "_watch": True}]},
}

def put(path, data):
    new = json.dumps(data, indent=2) + "\n"
    try:
        if open(path).read() == new: return
    except OSError: pass
    tmp = path + ".tmp"
    with open(tmp, "w") as f: f.write(new)
    os.replace(tmp, path)

put(os.path.join(ext_dir, "package.json"), pkg)
put(os.path.join(ext_dir, "themes", "island-color-theme.json"), theme)

# Register in extensions.json (VSCodium only loads what's listed there).
reg_path = os.path.join(ext_root, "extensions.json")
try: reg = json.load(open(reg_path))
except (OSError, ValueError): reg = []
if not any(e.get("identifier", {}).get("id") == EXT_ID for e in reg):
    reg.append({"identifier": {"id": EXT_ID}, "version": VER,
                "location": {"$mid": 1, "path": ext_dir, "scheme": "file"},
                "relativeLocation": f"{EXT_ID}-{VER}",
                "metadata": {"installedTimestamp": int(time.time() * 1000), "source": "vsix"}})
    with open(reg_path + ".tmp", "w") as f: json.dump(reg, f)
    os.replace(reg_path + ".tmp", reg_path)
