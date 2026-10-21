extends CanvasLayer
## Minimal HUD: flight stats (top-left), result banner (top-centre), controls (bottom).

var stats: Label
var banner: Label
var help: Label
var _banner_t := 0.0


func _ready() -> void:
	stats = _label(20)
	stats.position = Vector2(18, 14)
	banner = _label(38)
	banner.anchor_right = 1.0
	banner.offset_top = 70.0
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help = _label(16)
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.anchor_right = 1.0
	help.offset_left = 18.0
	help.offset_top = -34.0
	help.modulate = Color(1, 1, 1, 0.75)
	help.text = "W/S pull/reverse   A/D turn   Up/Down pitch   Space lift   Shift brake+hover   E drop present   V camera   R restart"


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(l)
	return l


func set_stats(text: String) -> void:
	stats.text = text


func flash(text: String, color := Color.WHITE, seconds := 3.0) -> void:
	banner.text = text
	banner.modulate = color
	_banner_t = seconds


func _process(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
		banner.modulate.a = clampf(_banner_t, 0.0, 1.0)
