extends CanvasLayer
## Stylized night clock (top right): a half-dial from sunset (left) to sunrise (right), the moon
## riding the arc, little stars, and the time. Reads the shared night_clock node.

var clock: Node
var dial: Control
var label: Label


func _ready() -> void:
	layer = 5
	dial = Control.new()
	dial.anchor_left = 1.0
	dial.anchor_right = 1.0
	dial.offset_left = -190.0
	dial.offset_right = -18.0
	dial.offset_top = 12.0
	dial.offset_bottom = 112.0
	dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dial.draw.connect(_draw_dial)
	add_child(dial)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.1, 0.9))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.offset_left = -190.0
	label.offset_right = -18.0
	label.offset_top = 88.0
	add_child(label)


func _process(_delta: float) -> void:
	if clock == null:
		clock = get_tree().get_first_node_in_group("night_clock")
		if clock == null:
			return
	var h := float(clock.get("hour"))
	var scrub := Input.is_action_pressed("time_scrub")
	label.text = "%s%s" % [clock.call("clock_text", h), "  >>" if scrub else ""]
	dial.queue_redraw()


func _draw_dial() -> void:
	if clock == null:
		return
	var kk := clampf(float(clock.get("k")), 0.0, 1.0)
	var sz := dial.size
	var c := Vector2(sz.x * 0.5, sz.y - 14.0)
	var r := minf(sz.x * 0.45, sz.y - 22.0)
	# sky wedge: warm at the ends (sunset / sunrise), deep blue over the top
	var segs := 28
	for i in segs:
		var a0 := PI + PI * float(i) / segs
		var a1 := PI + PI * float(i + 1) / segs
		var t := float(i) / (segs - 1)
		var warm := pow(absf(t - 0.5) * 2.0, 3.0)
		var col := Color(0.1, 0.12, 0.3, 0.7).lerp(Color(0.95, 0.5, 0.25, 0.75), warm)
		dial.draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]), col)
	dial.draw_arc(c, r, PI, TAU, 40, Color(1, 0.95, 0.8, 0.9), 2.0, true)
	dial.draw_line(c + Vector2(-r - 6, 0), c + Vector2(r + 6, 0), Color(1, 0.95, 0.8, 0.9), 2.0, true)
	# hour ticks (every ~2 h of night)
	for i in 6:
		var a := PI + PI * float(i) / 5.0
		dial.draw_line(c + Vector2(cos(a), sin(a)) * (r - 5), c + Vector2(cos(a), sin(a)) * r, Color(1, 1, 1, 0.6), 1.5)
	# elapsed part of the rim glows
	dial.draw_arc(c, r - 1.0, PI, PI + PI * kk, 32, Color(1.0, 0.85, 0.4, 0.9), 3.0, true)
	# sun at the ends, moon riding the arc
	dial.draw_circle(c + Vector2(-r, 0), 6.0, Color(1.0, 0.6, 0.2, 0.9 * (1.0 - kk)))
	dial.draw_circle(c + Vector2(r, 0), 6.0, Color(1.0, 0.75, 0.35, 0.3 + 0.6 * kk))
	var a := PI + PI * kk
	var mp := c + Vector2(cos(a), sin(a)) * (r * 0.72)
	dial.draw_circle(mp, 8.0, Color(1.0, 0.96, 0.8))
	dial.draw_circle(mp + Vector2(3.5, -2.5), 7.0, Color(0.12, 0.13, 0.32, 0.95))  # crescent bite
