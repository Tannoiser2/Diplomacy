class_name UI
extends RefCounted
## Aiuti grafici condivisi. Tema «cancelleria del 1901»: panno verde del tavolo delle conferenze,
## mogano e ottone per i pannelli, pergamena per i documenti, ceralacca per gli avvisi.
## Caratteri liberi (OFL / Apache): Old Standard TT per testi e intestazioni (il carattere dei
## libri di inizio Novecento), Pinyon Script per i titoli (la calligrafia dei trattati),
## Special Elite per i dispacci (la macchina per scrivere dei telegrammi).

const BG := Color("#0f1614")
const PANNO := Color("#18342a")
const PANEL := Color("#1f1611")
const PANEL_L := Color("#33241a")
const PARCH := Color("#eadfc2")
const PARCH_D := Color("#cdbd97")
const INK := Color("#2b1d12")
const INK_L := Color("#5a4630")
const OTTONE := Color("#c2a257")
const OTTONE_L := Color("#ecd693")
const CERA := Color("#8e1b1b")
const CERA_L := Color("#d24a3c")
const TEXT := Color("#efe6cf")
const MUTED := Color("#ad9f82")
const VERDE := Color("#9fd08a")

static var _tex := {}
static var font_title: Font
static var font_head: Font
static var font_body: Font
static var font_ital: Font
static var font_tele: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	font_title = load("res://assets/fonts/PinyonScript-Regular.ttf")
	font_head = load("res://assets/fonts/OldStandard-Bold.ttf")
	font_body = load("res://assets/fonts/OldStandard-Regular.ttf")
	font_ital = load("res://assets/fonts/OldStandard-Italic.ttf")
	font_tele = load("res://assets/fonts/SpecialElite-Regular.ttf")


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


static func bandiera(p: int) -> Texture2D:
	return tex("res://assets/bandiere/b%d.png" % p)


static func panel_style(bg: Color, border: Color = OTTONE, bw := 2, radius := 6, margin := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func dark_style(radius := 8, alpha := 0.95) -> StyleBoxFlat:
	var sb := panel_style(Color(PANEL, alpha), Color(OTTONE, 0.7), 2, radius)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 12
	return sb


static func parch_style(radius := 4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex("res://assets/misc/pergamena.jpg")
	sb.set_content_margin_all(16)
	return sb


static func make_theme() -> Theme:
	init_fonts()
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 24
	t.set_color("font_color", "Label", TEXT)
	t.set_font("font", "Button", font_head)
	t.set_font_size("font_size", "Button", 24)
	t.set_color("font_color", "Button", OTTONE_L)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", OTTONE_L)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.5))
	var n := panel_style(PANEL_L, Color(OTTONE, 0.75), 2, 6, 10)
	n.content_margin_left = 18
	n.content_margin_right = 18
	var h := n.duplicate()
	h.bg_color = Color("#4a3423")
	h.border_color = OTTONE_L
	var pr := n.duplicate()
	pr.bg_color = Color("#5c2a1e")
	var di := n.duplicate()
	di.bg_color = Color(PANEL_L, 0.5)
	di.border_color = Color(OTTONE, 0.25)
	t.set_stylebox("normal", "Button", n)
	t.set_stylebox("hover", "Button", h)
	t.set_stylebox("pressed", "Button", pr)
	t.set_stylebox("disabled", "Button", di)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for cls in ["OptionButton", "CheckBox", "CheckButton"]:
		t.set_font("font", cls, font_head)
		t.set_font_size("font_size", cls, 22)
		t.set_color("font_color", cls, OTTONE_L)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, OTTONE_L)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "OptionButton", t.get_stylebox(st, "Button"))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", dark_style())
	t.set_stylebox("panel", "PopupMenu", panel_style(PANEL, OTTONE, 2, 4, 8))
	t.set_font("font", "PopupMenu", font_body)
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", OTTONE_L)
	t.set_constant("v_separation", "PopupMenu", 10)
	var le := panel_style(Color("#120d0a"), Color(OTTONE, 0.6), 2, 4, 8)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", panel_style(Color("#120d0a"), OTTONE_L, 2, 4, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_font_size("font_size", "LineEdit", 26)
	t.set_font("normal_font", "RichTextLabel", font_body)
	t.set_font("bold_font", "RichTextLabel", font_head)
	t.set_font("italics_font", "RichTextLabel", font_ital)
	t.set_font_size("normal_font_size", "RichTextLabel", 24)
	t.set_font_size("bold_font_size", "RichTextLabel", 24)
	t.set_font_size("italics_font_size", "RichTextLabel", 24)
	t.set_color("default_color", "RichTextLabel", TEXT)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(OTTONE, 0.55)
	sc.set_corner_radius_all(5)
	sc.content_margin_left = 6
	sc.content_margin_right = 6
	t.set_stylebox("grabber", "VScrollBar", sc)
	t.set_stylebox("grabber_highlight", "VScrollBar", sc)
	t.set_stylebox("grabber_pressed", "VScrollBar", sc)
	var scb := StyleBoxFlat.new()
	scb.bg_color = Color(0, 0, 0, 0.25)
	scb.content_margin_left = 6
	scb.content_margin_right = 6
	t.set_stylebox("scroll", "VScrollBar", scb)
	return t


## Etichetta: per i testi lunghi dare sempre una larghezza minima (min_w) per evitare colonne di una lettera.
static func label(text: String, size := 24, color: Color = TEXT, font: Font = null, wrap := false, min_w := 0.0) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = maxf(min_w, 220.0)
	return l


static func head(text: String, size := 28, color: Color = OTTONE_L) -> Label:
	init_fonts()
	return label(text, size, color, font_head)


static func title(text: String, size := 110, color: Color = OTTONE_L) -> Label:
	init_fonts()
	var l := label(text, size, color, font_title)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 4)
	return l


static func button(text: String, cb: Callable, min_w := 0.0, size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.custom_minimum_size.y = maxf(52.0, size * 2.1)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## Pulsante principale (ceralacca).
static func primary(text: String, cb: Callable, min_w := 0.0, size := 26) -> Button:
	var b := button(text, cb, min_w, size)
	var n := panel_style(CERA, OTTONE_L, 2, 6, 10)
	n.content_margin_left = 22
	n.content_margin_right = 22
	var h := n.duplicate()
	h.bg_color = Color("#a82a22")
	var d := n.duplicate()
	d.bg_color = Color(CERA, 0.35)
	d.border_color = Color(OTTONE, 0.3)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_color_override("font_color", Color("#fff3d6"))
	return b


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer(w := 0.0, h := 0.0, expand := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func panel(style: StyleBox = null) -> PanelContainer:
	var p := PanelContainer.new()
	if style != null:
		p.add_theme_stylebox_override("panel", style)
	return p


static func flag_rect(p: int, h := 34.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = bandiera(p)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(h * 1.5, h)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func scroll(content: Control, min_h := 0.0) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.y = min_h
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


## Sfondo: il panno verde del tavolo, con una vignettatura.
class Backdrop extends Control:
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = -10

	func _draw() -> void:
		var t := UI.tex("res://assets/misc/panno.jpg")
		if t != null:
			draw_texture_rect(t, Rect2(Vector2.ZERO, size), true)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), UI.PANNO)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
