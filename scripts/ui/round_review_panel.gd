extends PanelContainer

signal next_round
signal settings_requested
var heading: Label
var summary: Label
var content: VBoxContainer
var notice: Label
var report: Dictionary = {}
var shot_review: VBoxContainer
var scroll: ScrollContainer


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#202322")
	style.border_color = Color("#535955")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(22)
	add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)
	heading = _text("", 24)
	layout.add_child(heading)
	summary = _text("", 16)
	summary.modulate = Color("#79e8e2")
	layout.add_child(summary)
	layout.add_child(HSeparator.new())
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	notice = _text("", 13)
	notice.modulate = Color("#bec5c1")
	layout.add_child(notice)
	var buttons := HBoxContainer.new()
	layout.add_child(buttons)
	var settings_button := Button.new()
	settings_button.text = "调整设置"
	settings_button.custom_minimum_size = Vector2(130, 38)
	settings_button.pressed.connect(func(): settings_requested.emit())
	buttons.add_child(settings_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var next := Button.new()
	next.text = "下一轮"
	next.custom_minimum_size = Vector2(150, 38)
	next.pressed.connect(func(): next_round.emit())
	buttons.add_child(next)
	hide()


func display(value: Dictionary) -> void:
	report = value.duplicate(true)
	heading.text = "回合复盘 · " + str(value.title)
	var accuracy := "--" if value.accuracy < 0 else "%.1f%%" % value.accuracy
	summary.text = "%.1f秒   命中 %s   %d / %d发   理论伤害 %d" % [
		value.seconds, accuracy, value.hits, value.shots, value.damage]
	if value.get("sniper", false):
		summary.text = "%d分制   玩家 %d : %d Bot\n%.1f秒   命中 %s   %d / %d发" % [
			value.limit, value.player_points, value.bot_points, value.seconds, accuracy, value.hits, value.shots]
	if value.has("score"):
		var score: Dictionary = value.score
		if value.get("sniper", false):
			summary.text += "\n走位奖励 +%.2f（上限 %.0f%%，不计入胜负比分）" % [
				score.bonus, score.weight] if score.valid else "\n本轮非计分"
		else:
			summary.text += "\n积分 %.1f = 命中 %.1f + 走位 %.1f（上限 %.0f%%）" % [
				score.total, score.base, score.bonus, score.weight] if score.valid else "\n本轮非计分"
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	shot_review = null
	scroll.scroll_vertical = 0
	if value.get("sniper", false):
		shot_review = preload("res://scripts/ui/shot_review.gd").new()
		content.add_child(shot_review)
		shot_review.load_shots(value.get("shot_snapshots", []), int(value.get("dropped_snapshots", 0)))
		content.add_child(HSeparator.new())
	for section in value.sections:
		content.add_child(_text(section.title, 18))
		for line in section.lines:
			content.add_child(_text(line, 14))
		content.add_child(HSeparator.new())
	notice.text = value.notice
	show()


func _text(value: String, font_size: int) -> Label:
	var text := Label.new()
	text.text = value
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", font_size)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return text
