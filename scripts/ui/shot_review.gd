extends VBoxContainer

var rows: Array = []
var filtered: Array = []
var select: OptionButton
var misses: CheckButton
var previous: Button
var next: Button
var diagram: Control
var detail: Label
var selected: Dictionary = {}
var range_degrees := 5.0


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var header := Label.new()
	header.text = "逐枪复盘 · 射击瞬间"
	header.add_theme_font_size_override("font_size", 18)
	add_child(header)
	var navigation := HBoxContainer.new()
	add_child(navigation)
	previous = Button.new()
	previous.text = "上一枪"
	previous.pressed.connect(func(): _show(select.selected - 1))
	navigation.add_child(previous)
	select = OptionButton.new()
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.item_selected.connect(_show)
	navigation.add_child(select)
	next = Button.new()
	next.text = "下一枪"
	next.pressed.connect(func(): _show(select.selected + 1))
	navigation.add_child(next)
	misses = CheckButton.new()
	misses.text = "只看未命中"
	misses.toggled.connect(func(_value: bool): _filter())
	navigation.add_child(misses)
	diagram = Control.new()
	diagram.custom_minimum_size = Vector2(0, 180)
	diagram.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diagram.draw.connect(_draw_diagram)
	diagram.resized.connect(func(): diagram.queue_redraw())
	add_child(diagram)
	detail = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 14)
	add_child(detail)


func load_shots(value: Array, dropped: int) -> void:
	rows = value.duplicate(true)
	if dropped > 0:
		var warning := Label.new()
		warning.text = "仅保留最近512枪；更早的%d枪仍计入总统计。" % dropped
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(warning)
	_filter()


func _filter() -> void:
	var keep := int(selected.get("number", -1))
	filtered.clear()
	select.clear()
	var index := 0
	for row in rows:
		if misses.button_pressed and row.hit:
			continue
		if row.number == keep:
			index = filtered.size()
		filtered.append(row)
		select.add_item("第%d枪 · %.2fs · %s" % [row.number, row.time, "命中" if row.hit else "未命中"])
	_show(index)


func _show(index: int) -> void:
	if filtered.is_empty():
		selected = {}
		select.disabled = true
		previous.disabled = true
		next.disabled = true
		detail.text = "没有未命中的记录。" if misses.button_pressed else "本轮没有射击记录。"
		diagram.queue_redraw()
		return
	index = clampi(index, 0, filtered.size() - 1)
	select.disabled = false
	select.select(index)
	selected = filtered[index]
	previous.disabled = index == 0
	next.disabled = index == filtered.size() - 1
	range_degrees = maxf(2, ceilf(maxf(absf(selected.horizontal), absf(selected.vertical)) * 1.2))
	var horizontal := "右" if selected.horizontal >= 0 else "左"
	var vertical := "上" if selected.vertical >= 0 else "下"
	var input_move: Vector2 = selected.input_move
	var keys := ("前" if input_move.y < 0 else ("后" if input_move.y > 0 else "")) \
		+ ("左" if input_move.x < 0 else ("右" if input_move.x > 0 else ""))
	if keys.is_empty():
		keys = "无"
	var lateral := "右" if selected.lateral_speed >= 0 else "左"
	var forward := "前" if selected.forward_speed >= 0 else "后"
	var status: String = "命中目标" if selected.hit else selected.trace
	if not selected.hit and selected.out_of_range:
		status += "；目标中心超出射程"
	if not selected.hit and selected.center_blocked:
		status += "；目标中心视线被挡"
	detail.text = "%s  /  %s  /  目标距离 %.2fm\n准星相对目标中心：偏%s %.2f°，偏%s %.2f°；总角度 %.2f°\n输入方向：%s；实际移动：%s %.2f、%s %.2f、垂直 %+.2f m/s\n图中十字=目标中心，圆点=准星；每轴 ±%.0f°，自动缩放。\n这是模拟射击步的角度示意，不是弹孔或命中体积；击中场景也可能是打偏后落在背景墙，不自动归因为遮挡。" % [
		status, "%.1f倍开镜" % selected.zoom if selected.scoped else "腰射", selected.distance,
		horizontal, absf(selected.horizontal), vertical, absf(selected.vertical), selected.angle,
		keys, lateral, absf(selected.lateral_speed), forward, absf(selected.forward_speed), selected.vertical_speed, range_degrees]
	diagram.queue_redraw()


func _draw_diagram() -> void:
	var center := diagram.size / 2
	var radius := minf(diagram.size.x * 0.4, diagram.size.y * 0.42)
	diagram.draw_rect(Rect2(Vector2.ZERO, diagram.size), Color("#151c20"))
	diagram.draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color("#586c74"), 1)
	diagram.draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color("#586c74"), 1)
	diagram.draw_arc(center, radius, 0, TAU, 64, Color("#34464e"), 1, true)
	if selected.is_empty():
		return
	var point := center + Vector2(selected.horizontal, -selected.vertical) * radius / range_degrees
	var color := Color("#79e8e2") if selected.hit else Color("#ff958b")
	diagram.draw_line(center, point, color.darkened(0.3), 1, true)
	diagram.draw_circle(point, 5, color)
