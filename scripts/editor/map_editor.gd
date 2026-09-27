extends Control

const DOC = preload("res://scripts/maps/map_document.gd")
const GEOMETRY = preload("res://scripts/maps/map_geometry.gd")
const FACES = preload("res://scripts/editor/box_faces.gd")
const EDGES = preload("res://scripts/editor/selection_edges.gd")
const TITLES := {"box": "白盒", "stairs": "楼梯", "ramp": "斜坡", "barrier": "阻挡体积"}
const ICON_NAMES := {"+": "file-plus", "▤": "folder-open", "▣": "save", "⇩": "download",
	"↶": "undo-2", "↷": "redo-2", "⧉": "copy", "×": "trash", "↖": "mouse-pointer-2",
	"✥": "move-3d", "□": "box", "阶": "list-ordered", "坡": "triangle-right",
	"阻挡": "shield", "P": "user-round", "B": "bot", "◎": "focus",
	"↻": "rotate-cw", "⊤": "scan", "缩放": "scaling"}
var document
var workspace: Node
var viewport_panel: SubViewportContainer
var viewport: SubViewport
var world: Node3D
var geometry: Node3D
var camera: Camera3D
var markers: Node3D
var selection: MeshInstance3D
var handles: Node3D
var inspector: VBoxContainer
var objects: ItemList
var status: Label
var map_name: LineEdit
var snap_control: SpinBox
var plane_control: SpinBox
var tools: Dictionary = {}
var undo_button: Button
var redo_button: Button
var picker: FileDialog
var confirm: ConfirmationDialog
var pending_action := ""
var export_only := false
var tool := "select"
var flying := false
var top_view := false
var preview: Node3D
var draft: Dictionary = {}
var drawing := false
var raising := false
var drag_start := Vector3.ZERO
var raise_mouse := Vector2.ZERO
var moving := false
var drag_axis := -1
var drag_mouse := Vector2.ZERO
var drag_origin := Vector3.ZERO
var drag_plane := 0.0
var drag_checkpoint := false
var syncing := false
var field_controls: Dictionary = {}
var tool_group := ButtonGroup.new()
var gesture_mouse := Vector2.ZERO
var footprint_dragged := false
var settings_tabs: TabBar
var ground: StaticBody3D
var reference_grid: MeshInstance3D
var orbiting := false
var orbit_pivot := Vector3.ZERO
var hover_preview: StaticBody3D
var placement_yaw := 0.0
var slider_gesture := false
var slider_checkpoint := false
var scale_origin := Vector3.ONE
var face_handles: Node3D
var face_highlight: MeshInstance3D
var active_face := -1
var hovered_face := -1
var face_dragging := false
var face_original: Dictionary = {}
var panel_face_original: Dictionary = {}
var face_plane := Plane()
var face_plane_start := Vector3.ZERO
var face_direction := Vector3.ZERO
var face_mouse_start := Vector2.ZERO
var face_uses_plane := false
var face_units_per_pixel := 0.01
var face_checkpoint := false
var face_previous_redo: Array[Dictionary] = []
var footprint_click_mode := false
var height_adjusted := false
var placement_confirm_pressed := false
var raise_origin_height := 0.0
var section_expanded := {"变换": false}


func _ready() -> void:
	workspace = get_node("/root/MapWorkspace")
	document = workspace.document
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = true
	get_tree().auto_accept_quit = false
	get_window().content_scale_size = Vector2i.ZERO
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_build_ui()
	_build_world()
	if not workspace.editor_view.is_empty():
		camera.position = workspace.editor_view.position
		camera.rotation = workspace.editor_view.rotation
		top_view = workspace.editor_view.top_view
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL if top_view else Camera3D.PROJECTION_PERSPECTIVE
		camera.size = workspace.editor_view.get("size", 42.0)
		orbit_pivot = workspace.editor_view.get("pivot", Vector3.ZERO)
	_rebuild()
	if not workspace.launch_error.is_empty():
		status.text = workspace.launch_error
		workspace.launch_error = ""


func _exit_tree() -> void:
	_stop_flying()
	get_tree().auto_accept_quit = true


func _build_ui() -> void:
	var ui_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Segoe UI Symbol", "Microsoft YaHei"])
	ui_theme.default_font = font
	ui_theme.default_font_size = 14
	theme = ui_theme
	var background := ColorRect.new()
	background.color = Color("#222426")
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#393d40") if state == "hover" else Color("#292c2e")
		if state == "pressed":
			style.bg_color = Color("#3d5756")
		style.set_corner_radius_all(3)
		style.content_margin_left = 8
		style.content_margin_right = 8
		ui_theme.set_stylebox(state, "Button", style)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size.y = 48
	toolbar.add_theme_constant_override("separation", 4)
	layout.add_child(toolbar)
	map_name = LineEdit.new()
	map_name.custom_minimum_size.x = 160
	map_name.max_length = 64
	map_name.tooltip_text = "关卡名称"
	toolbar.add_child(map_name)
	map_name.text_submitted.connect(func(_text: String): _commit_name())
	map_name.focus_exited.connect(_commit_name)
	_button(toolbar, "+", "新建地图", func(): _request_action("new"))
	_button(toolbar, "▤", "打开 .lgmap", func(): _request_action("open"))
	_button(toolbar, "▣", "保存地图 · Ctrl+S", save)
	_button(toolbar, "⇩", "导出 .lgmap", func(): _choose_save(true))
	toolbar.add_child(VSeparator.new())
	undo_button = _button(toolbar, "↶", "撤销 · Ctrl+Z", undo)
	redo_button = _button(toolbar, "↷", "重做 · Ctrl+Y", redo)
	_button(toolbar, "⧉", "复制选中物体 · Ctrl+D", duplicate_selected)
	_button(toolbar, "×", "删除选中物体 · Delete", delete_selected)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	_button(toolbar, "▶ 试玩", "进入当前关卡，Esc 面板可返回编辑", play, 90)
	_button(toolbar, "训练器", "返回默认训练场", func(): _request_action("training"), 78)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	layout.add_child(content)
	var rail := VBoxContainer.new()
	rail.custom_minimum_size.x = 48
	content.add_child(rail)
	for spec in [["select", "↖", "选择 / 推拉面 · 调整整体长宽高，对侧边界固定"], ["move", "✥", "移动 · 拖动轴向手柄"],
		["scale", "缩放", "缩放 · 拖动轴向手柄"],
		["box", "□", "白盒 · 拖底面，松开后拉高度，单击完成"],
		["stairs", "阶", "楼梯 · 先确认底面，再拉高确认；沿局部 -Z 上升"],
		["ramp", "坡", "斜坡 · 先确认底面，再拉高确认；沿局部 -Z 上升"],
		["barrier", "阻挡", "阻挡体积 · 编辑器可见，游戏中不可见，有实体碰撞"],
		["player", "P", "放置玩家出生点"], ["bot", "B", "放置 Bot 出生点"]]:
		var key: String = spec[0]
		var button := _button(rail, spec[1], spec[2], func(): set_tool(key), 44)
		button.toggle_mode = true
		button.button_group = tool_group
		tools[key] = button
	tools.select.button_pressed = true
	rail.add_child(HSeparator.new())
	_button(rail, "⊤", "切换俯视 / 透视", toggle_view, 44)
	_button(rail, "◎", "聚焦选中物体 · F", focus_selected, 44)
	_button(rail, "↻", "选中物体旋转 90°", rotate_selected, 44)
	viewport_panel = SubViewportContainer.new()
	viewport_panel.stretch = true
	viewport_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_panel.custom_minimum_size = Vector2(240, 200)
	viewport_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	content.add_child(viewport_panel)
	viewport = SubViewport.new()
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport_panel.add_child(viewport)
	viewport_panel.gui_input.connect(_viewport_input)
	viewport_panel.mouse_exited.connect(func():
		if not face_dragging:
			hovered_face = -1
			_update_face_visuals())
	var sidebar_margin := MarginContainer.new()
	sidebar_margin.custom_minimum_size.x = 352
	for edge in ["left", "right", "top", "bottom"]:
		sidebar_margin.add_theme_constant_override("margin_" + edge, 12)
	content.add_child(sidebar_margin)
	var sidebar := VBoxContainer.new()
	sidebar.add_theme_constant_override("separation", 10)
	sidebar_margin.add_child(sidebar)
	_label(sidebar, "场景物体")
	objects = ItemList.new()
	objects.custom_minimum_size.y = 88
	objects.allow_reselect = true
	objects.item_selected.connect(func(index: int): select_id(int(objects.get_item_metadata(index))))
	sidebar.add_child(objects)
	settings_tabs = TabBar.new()
	settings_tabs.add_tab("物体")
	settings_tabs.add_tab("地图")
	settings_tabs.tab_changed.connect(func(_index: int): _refresh_inspector())
	sidebar.add_child(settings_tabs)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 8)
	sidebar.add_child(options)
	_label(options, "吸附")
	snap_control = _spin(options, 0, 2, 0.1, 0.5, func(_v: float): pass)
	snap_control.tooltip_text = "网格间隔，0 为关闭吸附"
	_label(options, "平面 Y")
	plane_control = _spin(options, -16, 32, 0.1, 0, func(_v: float): pass)
	plane_control.tooltip_text = "没有命中表面时使用的建造平面高度"
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 8)
	scroll.add_child(inspector)
	status = Label.new()
	status.custom_minimum_size.y = 28
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout.add_child(status)
	picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray(["*.lgmap ; LG Trainer Map"])
	picker.file_selected.connect(_file_selected)
	add_child(picker)
	confirm = ConfirmationDialog.new()
	confirm.title = "未保存的地图"
	confirm.dialog_text = "放弃未保存的修改？"
	confirm.ok_button_text = "放弃修改"
	confirm.cancel_button_text = "取消"
	confirm.confirmed.connect(_perform_action)
	add_child(confirm)


func _button(parent: Node, text: String, tip: String, callback: Callable, width: float = 36) -> Button:
	var button := Button.new()
	button.text = text
	if ICON_NAMES.has(text):
		var path := "res://assets/editor/icons/%s.svg" % ICON_NAMES[text]
		if ResourceLoader.exists(path):
			button.icon = load(path) as Texture2D
			button.text = ""
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(width, 36)
	if text.length() == 1:
		button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _spin(parent: Node, low: float, high: float, step: float, value: float, callback: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.custom_minimum_size.x = 64
	spin.custom_minimum_size.y = 30
	spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spin.value_changed.connect(callback)
	parent.add_child(spin)
	spin.get_line_edit().gui_input.connect(func(event: InputEvent): _number_wheel(event, spin))
	return spin


func _number_wheel(event: InputEvent, spin: SpinBox) -> void:
	if event is InputEventMouseButton and event.pressed \
		and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] \
		and (spin.get_line_edit().has_focus() or event.alt_pressed):
		var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		spin.value += direction * spin.step * (10 if event.shift_pressed else 1)
		spin.get_line_edit().accept_event()


func _build_world() -> void:
	world = Node3D.new()
	viewport.add_child(world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#72777b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.3
	environment_node.environment = environment
	world.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.45
	sun.shadow_enabled = true
	world.add_child(sun)
	camera = Camera3D.new()
	camera.position = Vector3(16, 18, 22) if document.data.objects.is_empty() else Vector3(23, 26, 30)
	camera.far = 500
	camera.near = 0.05
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	geometry = Node3D.new()
	world.add_child(geometry)
	markers = Node3D.new()
	world.add_child(markers)
	selection = MeshInstance3D.new()
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/materials/selection_edge.gdshader")
	selection.material_override = material
	selection.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	selection.extra_cull_margin = 0.2
	world.add_child(selection)
	face_handles = Node3D.new()
	world.add_child(face_handles)
	for face in 6:
		var handle := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 12
		sphere.rings = 6
		handle.mesh = sphere
		var handle_material := StandardMaterial3D.new()
		handle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		handle_material.albedo_color = Color("#ffc36a")
		handle.material_override = handle_material
		handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		face_handles.add_child(handle)
	face_highlight = MeshInstance3D.new()
	var face_material := StandardMaterial3D.new()
	face_material.albedo_color = Color(1.0, 0.65, 0.2, 0.13)
	face_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	face_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_highlight.material_override = face_material
	face_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(face_highlight)
	handles = Node3D.new()
	world.add_child(handles)
	for axis in 3:
		var body := StaticBody3D.new()
		body.collision_layer = 16
		body.collision_mask = 0
		body.set_meta("axis", axis)
		var direction := Vector3.ZERO
		direction[axis] = 1
		body.position = direction * 1.1
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.1, 0.1, 0.1) + direction * 1.9
		mesh.mesh = box
		var color := StandardMaterial3D.new()
		color.albedo_color = [Color("#f47676"), Color("#8ce697"), Color("#79b9f4")][axis]
		color.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		color.no_depth_test = true
		mesh.material_override = color
		body.add_child(mesh)
		var arrow := MeshInstance3D.new()
		arrow.name = "Arrow"
		var cone := CylinderMesh.new()
		cone.top_radius = 0
		cone.bottom_radius = 0.18
		cone.height = 0.4
		arrow.mesh = cone
		arrow.quaternion = Quaternion(Vector3.UP, direction)
		arrow.position = direction * 1.1
		arrow.material_override = color
		body.add_child(arrow)
		var cap := MeshInstance3D.new()
		cap.name = "ScaleHead"
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * 0.3
		cap.mesh = cube
		cap.position = direction * 1.1
		cap.material_override = color
		body.add_child(cap)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.24, 0.24, 0.24) + direction * 1.9
		collision.shape = shape
		body.add_child(collision)
		handles.add_child(body)
	var grid := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(256, 256)
	grid.mesh = plane
	grid.position.y = -1.03
	var grid_material := ShaderMaterial.new()
	grid_material.shader = preload("res://assets/materials/whitebox_checker.gdshader")
	grid_material.set_shader_parameter("base_color", Color("#777b7e"))
	grid_material.set_shader_parameter("cell_size", 2.0)
	grid.material_override = grid_material
	world.add_child(grid)
	reference_grid = grid


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _rebuild() -> void:
	_clear_children(geometry)
	if is_instance_valid(ground):
		world.remove_child(ground)
		ground.queue_free()
	ground = null
	if document.data.get("infinite_ground", false):
		ground = preload("res://scripts/maps/infinite_ground.gd").new()
		world.add_child(ground)
	reference_grid.visible = ground == null
	for item in document.data.objects:
		geometry.add_child(GEOMETRY.build_object(item, true))
	_refresh_list()
	_refresh_markers()
	_refresh_inspector()
	_update_selection()
	_refresh_status()


func _refresh_object() -> void:
	var old := geometry.get_node_or_null("Object_%d" % document.selected)
	if old != null:
		geometry.remove_child(old)
		old.queue_free()
	var item: Dictionary = document.object_by_id(document.selected)
	if not item.is_empty():
		geometry.add_child(GEOMETRY.build_object(item, true))
	_update_selection()
	_refresh_status()


func _refresh_list() -> void:
	objects.clear()
	for item in document.data.objects:
		var index := objects.add_item("%s  #%d" % [TITLES[item.kind], int(item.id)])
		objects.set_item_metadata(index, int(item.id))
		if int(item.id) == document.selected:
			objects.select(index)


func _refresh_markers() -> void:
	_clear_children(markers)
	for key in ["player_spawn", "bot_spawn"]:
		var marker := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.8
		marker.mesh = capsule
		marker.position = DOC.vector3(document.data[key]) + Vector3.UP * 0.9
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#49cfba") if key == "player_spawn" else Color("#e6b65d")
		marker.material_override = material
		markers.add_child(marker)
		var direction := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.1, 0.1, 1.5)
		direction.mesh = box
		direction.material_override = material
		var yaw: float = document.data.player_yaw if key == "player_spawn" else document.data.bot_yaw
		direction.position = marker.position + Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw)) * 0.7
		direction.rotation.y = deg_to_rad(yaw)
		markers.add_child(direction)
	# The bake extent is a map setting, not a physical wall or a kill fence.
	if settings_tabs.current_tab != 1:
		return
	var b: Array = document.data.bounds
	var boundary := ImmediateMesh.new()
	boundary.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners := [Vector3(b[0], 0.04, b[1]), Vector3(b[2], 0.04, b[1]),
		Vector3(b[2], 0.04, b[3]), Vector3(b[0], 0.04, b[3])]
	for index in 4:
		boundary.surface_add_vertex(corners[index])
		boundary.surface_add_vertex(corners[(index + 1) % 4])
	boundary.surface_end()
	var outline := MeshInstance3D.new()
	outline.mesh = boundary
	var line := StandardMaterial3D.new()
	line.albedo_color = Color("#e7bf76")
	line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.material_override = line
	markers.add_child(outline)


func select_id(id: int) -> void:
	if document.selected != id:
		active_face = -1
		hovered_face = -1
	document.selected = id
	if id >= 0:
		settings_tabs.current_tab = 0
	_refresh_list()
	_refresh_inspector()
	_update_selection()


func _update_selection() -> void:
	var item: Dictionary = document.object_by_id(document.selected)
	selection.visible = not item.is_empty()
	handles.visible = selection.visible and tool in ["move", "scale"]
	for handle in handles.get_children():
		handle.collision_layer = 16 if handles.visible else 0
		handle.get_node("Arrow").visible = tool == "move"
		handle.get_node("ScaleHead").visible = tool == "scale"
	if item.is_empty():
		_update_face_visuals()
		return
	selection.mesh = EDGES.build(item)
	selection.position = DOC.vector3(item.position) + Vector3.UP * float(item.size[1]) * 0.5
	selection.rotation.y = deg_to_rad(item.yaw)
	handles.position = selection.position
	handles.rotation.y = deg_to_rad(item.yaw) if tool == "scale" else 0.0
	_update_face_visuals()


func _refresh_inspector() -> void:
	syncing = true
	_clear_children(inspector)
	field_controls.clear()
	map_name.text = document.data.name
	var item: Dictionary = document.object_by_id(document.selected)
	if settings_tabs.current_tab == 0 and not item.is_empty():
		_label(inspector, "%s  #%d" % [TITLES[item.kind], int(item.id)])
		_vector_fields("尺寸 / m", "size", item.size, 0.1, 64)
		if item.kind in DOC.KINDS:
			_face_fields(item)
		if item.kind == "stairs":
			_section_header("楼梯")
			var automatic := CheckBox.new()
			automatic.text = "自动可行走楼梯"
			automatic.button_pressed = item.get("auto_steps", false)
			automatic.tooltip_text = "单阶最高 0.25 m、踏面至少 0.4 m；过陡时自动延长楼梯"
			automatic.toggled.connect(func(enabled: bool): _edit_object("auto_steps", enabled))
			inspector.add_child(automatic)
			_numeric_field("阶数", "steps", item.steps, 1, 64, 1)
			field_controls.steps.editable = not item.get("auto_steps", false)
			var details := _label(inspector, "")
			details.name = "StairInfo"
		elif item.kind == "ramp":
			var details := _label(inspector, "")
			details.name = "RampInfo"
		_vector_fields("底部位置 / m", "position", item.position, -128, 128)
		_numeric_field("旋转 Y / °", "yaw", item.yaw, -360, 360, 1)
		_section_header("材质")
		var colors := HBoxContainer.new()
		colors.add_theme_constant_override("separation", 8)
		inspector.add_child(colors)
		for index in DOC.COLORS.size():
			var swatch := Button.new()
			swatch.custom_minimum_size = Vector2(38, 26)
			swatch.tooltip_text = "游戏材质 · " + ["灰", "深灰", "白", "青", "金"][index]
			var style := StyleBoxFlat.new()
			style.bg_color = Color(DOC.COLORS[index])
			style.border_color = Color.WHITE if int(item.color) == index else Color("#30383a")
			style.set_border_width_all(2)
			swatch.add_theme_stylebox_override("normal", style)
			swatch.pressed.connect(func(): _edit_object("color", index))
			colors.add_child(swatch)
	if settings_tabs.current_tab == 0:
		if item.is_empty():
			_label(inspector, "未选中物体")
		syncing = false
		_update_dimensions()
		_refresh_markers()
		return
	var floor_toggle := CheckBox.new()
	floor_toggle.text = "无限地面 · Y = 0"
	floor_toggle.button_pressed = document.data.get("infinite_ground", false)
	floor_toggle.toggled.connect(func(enabled: bool):
		document.checkpoint()
		document.data.infinite_ground = enabled
		_rebuild())
	inspector.add_child(floor_toggle)
	_label(inspector, "出生点")
	_vector_fields("玩家 / m", "player_spawn", document.data.player_spawn, -128, 128, true)
	_numeric_field("玩家朝向 / °", "player_yaw", document.data.player_yaw, -360, 360, 15, true)
	_vector_fields("Bot / m", "bot_spawn", document.data.bot_spawn, -128, 128, true)
	_numeric_field("Bot 朝向 / °", "bot_yaw", document.data.bot_yaw, -360, 360, 15, true)
	_label(inspector, "导航烘焙范围")
	for index in 4:
		_numeric_field(["X 最小 / m", "Z 最小 / m", "X 最大 / m", "Z 最大 / m"][index],
			"bounds:%d" % index, document.data.bounds[index], -128, 128, 0.5, true)
	_numeric_field("跌落重置 Y / m", "kill_y", document.data.kill_y, -128, 0, 0.5, true)
	syncing = false
	_update_dimensions()
	_refresh_markers()


func _section_header(title: String) -> void:
	var separator := HSeparator.new()
	separator.custom_minimum_size.y = 2
	inspector.add_child(separator)
	var label := _label(inspector, title)
	label.modulate = Color("#abb5ba")


func _transform_section() -> VBoxContainer:
	var existing := inspector.get_node_or_null("TransformFields")
	if existing != null:
		return existing
	inspector.add_child(HSeparator.new())
	var toggle := Button.new()
	toggle.name = "TransformToggle"
	toggle.text = ("▾ " if section_expanded["变换"] else "▸ ") + "变换"
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.flat = true
	toggle.custom_minimum_size.y = 30
	inspector.add_child(toggle)
	var fields := VBoxContainer.new()
	fields.name = "TransformFields"
	fields.add_theme_constant_override("separation", 8)
	fields.visible = section_expanded["变换"]
	inspector.add_child(fields)
	toggle.pressed.connect(func():
		section_expanded["变换"] = not section_expanded["变换"]
		fields.visible = section_expanded["变换"]
		toggle.text = ("▾ " if fields.visible else "▸ ") + "变换")
	return fields


func _vector_fields(title: String, key: String, values: Array, low: float, high: float, map_field: bool = false) -> void:
	var parent: Node = _transform_section() if key == "position" and not map_field else inspector
	if parent == inspector:
		_section_header(title)
	else:
		_label(parent, title)
	for axis in 3:
		var field := "%s:%d" % [key, axis]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		parent.add_child(row)
		var label := _label(row, ["X", "Y", "Z"][axis])
		label.custom_minimum_size.x = 18
		label.modulate = [Color("#ed9292"), Color("#9ed9ae"), Color("#97bce7")][axis]
		var spin := _spin(row, low, high, 0.1, values[axis],
			func(v: float): _edit_field(field, v, map_field))
		spin.tooltip_text = ["X", "Y", "Z"][axis]
		spin.custom_minimum_size.x = 104
		spin.size_flags_horizontal = Control.SIZE_FILL
		field_controls[field] = spin
		if not map_field:
			_add_slider(row, spin)


func _numeric_field(title: String, key: String, value: float, low: float, high: float, step: float, map_field: bool = false) -> void:
	var parent: Node = _transform_section() if key == "yaw" and not map_field else inspector
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := _label(row, title)
	label.custom_minimum_size.x = 138
	var spin := _spin(row, low, high, step, value, func(v: float): _edit_field(key, v, map_field))
	field_controls[key] = spin
	if not map_field and key == "yaw":
		_add_slider(parent, spin)


func _add_slider(parent: Node, spin: SpinBox) -> void:
	var slider := HSlider.new()
	slider.min_value = spin.min_value
	slider.max_value = spin.max_value
	slider.step = spin.step
	slider.value = spin.value
	slider.custom_minimum_size = Vector2(110, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.scrollable = false
	slider.drag_started.connect(func():
		slider_gesture = true
		slider_checkpoint = false)
	slider.drag_ended.connect(func(_changed: bool):
		slider_gesture = false
		_refresh_inspector())
	slider.value_changed.connect(func(value: float): spin.value = value)
	spin.value_changed.connect(func(value: float): slider.set_value_no_signal(value))
	parent.add_child(slider)


func _face_fields(item: Dictionary) -> void:
	_section_header("六面推拉")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	inspector.add_child(row)
	for face in 6:
		var button := Button.new()
		button.text = ["-X", "+X", "-Y", "+Y", "-Z", "+Z"][face]
		button.tooltip_text = ["左面", "右面", "底面", "顶面", "前面", "后面"][face] + " · 物体局部方向"
		button.toggle_mode = true
		button.button_pressed = active_face == face
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 30
		button.pressed.connect(func():
			active_face = face
			hovered_face = -1
			_refresh_inspector()
			_update_face_visuals())
		row.add_child(button)
	if active_face < 0:
		return
	panel_face_original = item.duplicate(true)
	var controls := HBoxContainer.new()
	inspector.add_child(controls)
	_label(controls, "面偏移 / m")
	var smallest := FACES.resized(item, active_face, -10000, 0)
	var largest := FACES.resized(item, active_face, 10000, 0)
	var axis := active_face / 2
	var offset := _spin(controls, smallest.size[axis] - item.size[axis],
		largest.size[axis] - item.size[axis], 0.01, 0, _panel_face_offset)
	offset.tooltip_text = "相对本次起点沿面法线移动；正数向外，负数向内，对面固定。自动楼梯拔高时会向入口延长"
	_add_slider(inspector, offset)


func _panel_face_offset(value: float) -> void:
	if syncing or active_face < 0 or panel_face_original.is_empty():
		return
	var item: Dictionary = document.object_by_id(document.selected)
	if item.is_empty():
		return
	var next := FACES.resized(panel_face_original, active_face, value, 0.0)
	if DOC.vector3(next.size).is_equal_approx(DOC.vector3(item.size)) \
		and DOC.vector3(next.position).is_equal_approx(DOC.vector3(item.position)):
		return
	if not slider_gesture or not slider_checkpoint:
		document.checkpoint()
		slider_checkpoint = slider_gesture
	item.size = next.size
	item.position = next.position
	item.steps = next.steps
	_refresh_object()
	_sync_object_fields(item)
	_update_dimensions()


func _world_units_per_pixel(point: Vector3) -> float:
	var pixels := camera.unproject_position(point + camera.basis.y).distance_to(camera.unproject_position(point))
	return 1.0 / maxf(pixels, 0.01)


func _update_face_visuals() -> void:
	if not is_instance_valid(face_handles):
		return
	var item: Dictionary = document.object_by_id(document.selected)
	var enabled: bool = not item.is_empty() and item.kind in DOC.KINDS and tool == "select"
	face_handles.visible = enabled
	face_highlight.visible = false
	if not enabled:
		return
	for face in 6:
		var handle: MeshInstance3D = face_handles.get_child(face)
		var at := FACES.surface_center(item, face)
		var normal := FACES.normal(face, item.yaw)
		var view := camera.basis.z if top_view else (camera.position - at).normalized()
		handle.visible = not camera.is_position_behind(at) and normal.dot(view) > 0.06
		handle.position = at + normal * 0.025
		handle.scale = Vector3.ONE * _world_units_per_pixel(at) * (13 if face == hovered_face else 10)
		handle.material_override.albedo_color = Color("#ffb64c") if face in [active_face, hovered_face] else Color("#d9dfe2")
	var face := active_face if face_dragging else hovered_face
	if face < 0:
		return
	# Curved stair profiles and wedge sides are not rectangular box faces.
	# Their handles and outline show the editable bounds without a false filled plane.
	if item.kind in ["stairs", "ramp"]:
		return
	var size := DOC.vector3(item.size)
	size[face / 2] = 0.008
	if face_highlight.mesh == null or not face_highlight.mesh.size.is_equal_approx(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		face_highlight.mesh = mesh
	face_highlight.position = FACES.center(item, face)
	face_highlight.rotation.y = deg_to_rad(item.yaw)
	face_highlight.visible = true


func _face_under_mouse(mouse: Vector2) -> Dictionary:
	if face_handles.visible:
		var selected: Dictionary = document.object_by_id(document.selected)
		for face in 6:
			var handle: MeshInstance3D = face_handles.get_child(face)
			if not handle.visible or camera.is_position_behind(handle.position):
				continue
			if camera.unproject_position(handle.position).distance_to(mouse) <= 9:
				var center_hit := _ray(camera.unproject_position(handle.position))
				var clear: bool = center_hit.is_empty() or center_hit.collider.get_meta("map_id", -1) == document.selected \
					or camera.position.distance_to(center_hit.position) >= camera.position.distance_to(handle.position) - 0.05
				if clear:
					return {"id": document.selected, "face": face, "point": FACES.surface_center(selected, face)}
	var hit := _ray(mouse)
	if hit.is_empty():
		return {}
	var id: int = hit.collider.get_meta("map_id", -1)
	var item: Dictionary = document.object_by_id(id)
	if item.is_empty() or not item.kind in DOC.KINDS:
		return {}
	return {"id": id, "face": FACES.picked_face(item, hit.normal), "point": hit.position}


func _begin_face_drag(face: int, mouse: Vector2, point: Vector3) -> void:
	active_face = face
	hovered_face = face
	face_original = document.object_by_id(document.selected).duplicate(true)
	face_mouse_start = mouse
	face_direction = FACES.normal(face, face_original.yaw)
	face_units_per_pixel = _world_units_per_pixel(point)
	var view := camera.basis.z if top_view else (camera.position - point).normalized()
	var plane_normal := view - face_direction * view.dot(face_direction)
	face_uses_plane = plane_normal.length() > 0.18
	if face_uses_plane:
		face_plane = Plane(plane_normal.normalized(), point)
		var intersection: Variant = face_plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
		face_uses_plane = intersection != null
		if face_uses_plane:
			face_plane_start = intersection
	face_checkpoint = false
	face_previous_redo = document.redo_stack.duplicate(true)
	face_dragging = true
	_update_face_visuals()


func _drag_face(mouse: Vector2) -> void:
	if mouse.distance_to(face_mouse_start) < 3 and not face_checkpoint:
		return
	var distance := (face_mouse_start.y - mouse.y) * face_units_per_pixel
	if face_uses_plane:
		var point: Variant = face_plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
		if point == null:
			return
		distance = (point - face_plane_start).dot(face_direction)
	var next := FACES.resized(face_original, active_face, distance, snap_control.value)
	var item: Dictionary = document.object_by_id(document.selected)
	if DOC.vector3(next.size).is_equal_approx(DOC.vector3(item.size)) \
		and DOC.vector3(next.position).is_equal_approx(DOC.vector3(item.position)):
		return
	if not face_checkpoint:
		document.checkpoint()
		face_checkpoint = true
	item.size = next.size
	item.position = next.position
	item.steps = next.steps
	_refresh_object()
	_sync_object_fields(item)
	_update_dimensions()


func _end_face_drag(cancel: bool = false) -> void:
	if not face_dragging:
		return
	var item: Dictionary = document.object_by_id(document.selected)
	var unchanged: bool = item.size == face_original.size and item.position == face_original.position \
		and item.steps == face_original.steps
	if face_checkpoint and (cancel or unchanged):
		document.undo()
		document.redo_stack = face_previous_redo
	face_dragging = false
	face_checkpoint = false
	hovered_face = -1
	_refresh_object()
	_refresh_inspector()


func _edit_field(key: String, value: float, map_field: bool) -> void:
	if syncing:
		return
	var target: Dictionary = document.data if map_field else document.object_by_id(document.selected)
	if target.is_empty():
		return
	if key.contains(":"):
		var parts := key.split(":")
		if target[parts[0]][int(parts[1])] == value:
			return
	elif target.get(key) == value:
		return
	if not slider_gesture or not slider_checkpoint:
		document.checkpoint()
		slider_checkpoint = slider_gesture
	if key.contains(":"):
		var parts := key.split(":")
		target[parts[0]][int(parts[1])] = value
	else:
		target[key] = value
	if not map_field:
		DOC.fit_stairs(target)
		_sync_object_fields(target)
	if map_field:
		_refresh_markers()
		_refresh_status()
	else:
		_refresh_object()
	_update_dimensions()


func _edit_object(key: String, value: Variant) -> void:
	if document.object_by_id(document.selected).is_empty():
		return
	document.checkpoint()
	document.object_by_id(document.selected)[key] = value
	DOC.fit_stairs(document.object_by_id(document.selected))
	_refresh_object()
	_refresh_inspector()


func _sync_object_fields(item: Dictionary) -> void:
	syncing = true
	for key in field_controls:
		var parts: PackedStringArray = key.split(":")
		if parts.size() == 2 and item.has(parts[0]):
			field_controls[key].value = item[parts[0]][int(parts[1])]
		elif item.has(key) and (item[key] is float or item[key] is int):
			field_controls[key].value = item[key]
	syncing = false


func _update_dimensions() -> void:
	var item: Dictionary = document.object_by_id(document.selected)
	if item.is_empty():
		return
	var stair := inspector.get_node_or_null("StairInfo")
	if stair != null:
		stair.text = "每阶 %.3f × %.3f m" % [item.size[1] / item.steps, item.size[2] / item.steps]
		stair.modulate = Color("#f1bf74") if item.size[1] / item.steps > 0.3 \
			or item.size[2] / item.steps < DOC.MIN_TREAD else Color.WHITE
	var ramp := inspector.get_node_or_null("RampInfo")
	if ramp != null:
		var angle := rad_to_deg(atan2(item.size[1], item.size[2]))
		ramp.text = "坡度 %.1f°" % angle
		ramp.modulate = Color("#f1bf74") if angle > 44 else Color.WHITE


func _commit_name() -> void:
	var text := map_name.text.strip_edges()
	if text.is_empty():
		map_name.text = document.data.name
	elif text != document.data.name:
		document.checkpoint()
		document.data.name = text
		_refresh_status()


func _refresh_status() -> void:
	undo_button.disabled = document.undo_stack.is_empty()
	redo_button.disabled = document.redo_stack.is_empty()
	status.text = "%s%s   |   %d / 256   |   %s" % [document.data.name,
		" *" if document.changed() else "", document.data.objects.size(),
		document.path if not document.path.is_empty() else "未保存"]


func set_tool(value: String) -> void:
	_cancel_gesture()
	tool = value
	hovered_face = -1
	for key in tools:
		tools[key].set_pressed_no_signal(key == value)
	_update_selection()
	_clear_hover()


func _ray(mouse: Vector2, mask: int = 1) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(camera.project_ray_origin(mouse),
		camera.project_ray_origin(mouse) + camera.project_ray_normal(mouse) * 600, mask)
	return viewport.world_3d.direct_space_state.intersect_ray(query)


func _on_plane(mouse: Vector2, height: float) -> Variant:
	return Plane(Vector3.UP, height).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))


func _point(mouse: Vector2) -> Variant:
	var hit := _ray(mouse)
	if not hit.is_empty():
		return hit.position
	return _on_plane(mouse, plane_control.value)


func _snapped(value: float) -> float:
	return snappedf(value, snap_control.value) if snap_control.value > 0 else value


func _placement(mouse: Vector2) -> Variant:
	var hit := _ray(mouse)
	var point: Variant = _point(mouse)
	if point == null:
		return null
	var at := Vector3(_snapped(point.x), point.y, _snapped(point.z))
	if not hit.is_empty() and hit.normal.y < 0.999:
		# The click is now a footprint corner, not the centre of a preset volume.
		at = point
	return at


func _clear_hover() -> void:
	if is_instance_valid(hover_preview):
		hover_preview.get_parent().remove_child(hover_preview)
		hover_preview.queue_free()
	hover_preview = null


func _hover(mouse: Vector2) -> void:
	if not tool in DOC.KINDS or drawing or raising or moving:
		_clear_hover()
		return
	var point: Variant = _placement(mouse)
	if point == null:
		_clear_hover()
		return
	if not is_instance_valid(hover_preview):
		var item := DOC.object_data(999999, "box", point, Vector3(0.3, 0.02, 0.3))
		hover_preview = GEOMETRY.build_object(item, true)
		hover_preview.collision_layer = 0
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.45, 0.85, 0.75, 0.4)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for child in hover_preview.get_children():
			if child is MeshInstance3D:
				child.material_override = material
		world.add_child(hover_preview)
	hover_preview.position = point
	hover_preview.rotation.y = deg_to_rad(placement_yaw)


func _viewport_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if face_dragging or drawing or raising:
				return
			orbiting = event.pressed
			if orbiting:
				_clear_hover()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and (drawing or raising or moving or face_dragging):
				_cancel_gesture()
				return
			if event.pressed and not drawing and not raising:
				flying = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				_stop_flying()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if face_dragging:
				return
			var sign_value := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if raising:
				_set_draft_height(_snapped(draft.size[1] - sign_value * maxf(0.1, snap_control.value)))
				raise_origin_height = draft.size[1]
				raise_mouse = event.position
				height_adjusted = true
				_update_preview()
			elif event.alt_pressed and tool in DOC.KINDS and not drawing:
				placement_yaw = wrapf(placement_yaw - sign_value * 15, -180, 180)
				_hover(event.position)
			elif top_view:
				camera.size = clampf(camera.size * pow(1.12, sign_value), 4, 200)
			else:
				var distance := camera.position.distance_to(orbit_pivot)
				camera.position += camera.basis.z * sign_value * clampf(distance * 0.12, 0.2, 20)
		elif event.button_index == MOUSE_BUTTON_LEFT and not flying and not orbiting:
			if event.pressed and event.double_click and tool in DOC.KINDS:
				return
			if event.pressed:
				_pointer_down(event.position)
			else:
				_pointer_up(event.position)
	elif event is InputEventMouseMotion and not flying:
		if orbiting:
			if event.shift_pressed or top_view:
				var factor := camera.size if top_view else camera.position.distance_to(orbit_pivot)
				var pan: Vector3 = (-camera.basis.x * event.relative.x + camera.basis.y * event.relative.y) \
					* factor / maxf(viewport.size.y, 1)
				camera.position += pan
				orbit_pivot += pan
			else:
				var distance := maxf(1, camera.position.distance_to(orbit_pivot))
				camera.rotation.y -= event.relative.x * 0.006
				camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.006, -1.5, 1.5)
				camera.position = orbit_pivot + camera.basis.z * distance
		else:
			_pointer_motion(event.position)
			_hover(event.position)
			if tool == "select" and not face_dragging:
				var face_hit := _face_under_mouse(event.position)
				hovered_face = face_hit.face if not face_hit.is_empty() and face_hit.id == document.selected else -1
				_update_face_visuals()


func _pointer_down(mouse: Vector2) -> void:
	if raising:
		placement_confirm_pressed = height_adjusted
		return
	if drawing:
		if footprint_click_mode:
			_pointer_motion(mouse)
			if footprint_dragged:
				_begin_raise(mouse)
		return
	if tool in DOC.KINDS:
		var point: Variant = _placement(mouse)
		if point == null:
			return
		drag_start = point
		draft = DOC.object_data(document.next_id(), tool, drag_start,
			Vector3(0.1, 0.1, 0.4 if tool == "stairs" else 0.1))
		draft.yaw = placement_yaw
		if tool == "stairs":
			draft.auto_steps = true
			DOC.fit_stairs(draft)
		_clear_hover()
		gesture_mouse = mouse
		footprint_dragged = false
		footprint_click_mode = false
		drawing = true
		_update_preview()
		return
	if tool in ["player", "bot"]:
		var point: Variant = _point(mouse)
		if point != null:
			document.checkpoint()
			document.data[tool + "_spawn"] = DOC.array3(Vector3(_snapped(point.x), point.y + 0.02, _snapped(point.z)))
			_refresh_markers()
			_refresh_inspector()
			_refresh_status()
		return
	if tool == "select":
		var face_hit := _face_under_mouse(mouse)
		if not face_hit.is_empty():
			select_id(face_hit.id)
			_begin_face_drag(face_hit.face, mouse, face_hit.point)
			return
	drag_axis = -1
	var handle_hit := _ray(mouse, 16) if tool in ["move", "scale"] else {}
	if not handle_hit.is_empty():
		drag_axis = int(handle_hit.collider.get_meta("axis"))
	else:
		var hit := _ray(mouse)
		if hit.is_empty():
			select_id(-1)
			return
		select_id(int(hit.collider.get_meta("map_id", -1)))
	if tool in ["move", "scale"] and document.selected >= 0:
		drag_origin = DOC.vector3(document.object_by_id(document.selected).position)
		scale_origin = DOC.vector3(document.object_by_id(document.selected).size)
		drag_plane = drag_origin.y
		var point: Variant = _on_plane(mouse, drag_plane)
		drag_start = drag_origin if point == null else point
		drag_mouse = mouse
		moving = true
		drag_checkpoint = false


func _pointer_motion(mouse: Vector2) -> void:
	if face_dragging:
		_drag_face(mouse)
	elif drawing:
		if mouse.distance_to(gesture_mouse) < 3:
			footprint_dragged = false
			return
		footprint_dragged = true
		var point: Variant = _on_plane(mouse, drag_start.y)
		if point != null:
			var local_delta: Vector3 = (point - drag_start).rotated(Vector3.UP, -deg_to_rad(draft.yaw))
			local_delta.x = _snapped(local_delta.x)
			local_delta.z = _snapped(local_delta.z)
			var minimum_depth := 0.4 if draft.kind == "stairs" and draft.get("auto_steps", false) else 0.1
			if absf(local_delta.x) < 0.1 or absf(local_delta.z) < minimum_depth:
				footprint_dragged = false
				return
			local_delta.x = clampf(local_delta.x, -64, 64)
			local_delta.z = clampf(local_delta.z, -64, 64)
			draft.position = DOC.array3(drag_start + local_delta.rotated(Vector3.UP, deg_to_rad(draft.yaw)) * 0.5)
			draft.size = [absf(local_delta.x), 0.1, absf(local_delta.z)]
			_update_preview()
	elif raising:
		if placement_confirm_pressed:
			return
		_set_draft_height(_snapped(raise_origin_height + (raise_mouse.y - mouse.y) * 0.025))
		if absf(raise_mouse.y - mouse.y) >= 3:
			height_adjusted = true
		_update_preview()
	elif moving:
		var at := drag_origin
		if tool == "scale":
			var axis := Vector3.ZERO
			axis[maxi(0, drag_axis)] = 1
			axis = axis.rotated(Vector3.UP, deg_to_rad(document.object_by_id(document.selected).yaw))
			var origin := drag_origin + Vector3.UP * scale_origin.y * 0.5
			var projected := camera.unproject_position(origin + axis) - camera.unproject_position(origin)
			if projected.length_squared() < 4:
				projected = Vector2(0, -40)
			var size := scale_origin
			if drag_axis < 0:
				size *= maxf(0.05, 1.0 + (mouse.x - drag_mouse.x) * 0.01)
			else:
				size[drag_axis] += (mouse - drag_mouse).dot(projected) / projected.length_squared()
			for index in 3:
				size[index] = clampf(_snapped(size[index]), 0.1, 64)
			if size.distance_to(scale_origin) > 0.001 and not drag_checkpoint:
				document.checkpoint()
				drag_checkpoint = true
			var item: Dictionary = document.object_by_id(document.selected)
			item.size = DOC.array3(size)
			DOC.fit_stairs(item)
			_refresh_object()
			return
		if drag_axis >= 0:
			var axis := Vector3.ZERO
			axis[drag_axis] = 1
			var origin := selection.position
			var projected := camera.unproject_position(origin + axis) - camera.unproject_position(origin)
			if projected.length_squared() < 4:
				projected = Vector2(0, -40)
			at[drag_axis] = _snapped(drag_origin[drag_axis] + (mouse - drag_mouse).dot(projected) / projected.length_squared())
		else:
			var point: Variant = _on_plane(mouse, drag_plane)
			if point == null:
				return
			at = drag_origin + point - drag_start
			at.x = _snapped(at.x)
			at.z = _snapped(at.z)
		at = at.clamp(Vector3.ONE * -128, Vector3.ONE * 128)
		if at.distance_to(drag_origin) > 0.001 and not drag_checkpoint:
			document.checkpoint()
			drag_checkpoint = true
		document.object_by_id(document.selected).position = DOC.array3(at)
		_refresh_object()


func _pointer_up(mouse: Vector2) -> void:
	if face_dragging:
		_end_face_drag()
		return
	if drawing:
		if not footprint_click_mode:
			_pointer_motion(mouse)
		if not footprint_dragged:
			footprint_click_mode = true
			return
		if not footprint_click_mode:
			_begin_raise(mouse)
	elif raising and placement_confirm_pressed:
		placement_confirm_pressed = false
		if commit_draft():
			set_tool("select")
	if moving:
		moving = false
		_refresh_inspector()


func _begin_raise(mouse: Vector2) -> void:
	drawing = false
	raising = true
	raise_mouse = mouse
	raise_origin_height = 0.0
	height_adjusted = false
	placement_confirm_pressed = false
	_update_preview()


func _set_draft_height(height: float) -> void:
	draft.size[1] = clampf(height, 0.1, maxf(0.1, FACES.height_limit(draft)))
	if draft.kind == "stairs" and draft.get("auto_steps", false):
		draft.steps = maxi(1, int(ceil(float(draft.size[1]) / DOC.MAX_RISE)))


func _update_preview() -> void:
	_set_draft_height(draft.size[1])
	if preview != null:
		world.remove_child(preview)
		preview.queue_free()
	var visual: Dictionary = draft.duplicate(true)
	if drawing:
		visual.kind = "box"
		visual.size[1] = 0.02
	preview = GEOMETRY.build_object(visual, true)
	preview.collision_layer = 0
	var edge := MeshInstance3D.new()
	edge.mesh = EDGES.build(visual)
	edge.material_override = selection.material_override
	edge.position.y = visual.size[1] * 0.5
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.add_child(edge)
	world.add_child(preview)
	status.text = "%s   %.2f × %.2f × %.2f m" % [TITLES[draft.kind], draft.size[0], draft.size[1], draft.size[2]]


func commit_draft() -> bool:
	if draft.is_empty():
		return false
	_set_draft_height(draft.size[1])
	var next: Dictionary = document.data.duplicate(true)
	next.objects.append(draft.duplicate(true))
	var error := DOC.validate(next)
	if not error.is_empty():
		status.text = error
		return false
	document.checkpoint()
	document.data = next
	document.selected = int(draft.id)
	_cancel_gesture()
	_rebuild()
	return true


func _cancel_gesture() -> void:
	_clear_hover()
	_end_face_drag(true)
	if moving and drag_checkpoint:
		document.undo()
	drawing = false
	raising = false
	footprint_click_mode = false
	placement_confirm_pressed = false
	height_adjusted = false
	moving = false
	draft = {}
	if is_instance_valid(preview):
		preview.get_parent().remove_child(preview)
		preview.queue_free()
	preview = null
	if is_instance_valid(geometry):
		_rebuild()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		orbiting = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_stop_flying()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed \
		and not viewport_panel.get_global_rect().has_point(event.position):
		if face_dragging:
			_end_face_drag()
		elif raising:
			placement_confirm_pressed = false
		elif moving:
			moving = false
			_refresh_inspector()
		elif drawing:
			_cancel_gesture()
	if flying and event is InputEventMouseMotion:
		if top_view:
			camera.position += Vector3(-event.relative.x, 0, -event.relative.y) * camera.size / maxf(viewport.size.y, 1)
		else:
			camera.rotation.y -= event.relative.x * 0.003
			camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.003, -1.5, 1.5)
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or picker.visible or confirm.visible:
		return
	if event.keycode == KEY_ESCAPE:
		_stop_flying()
		_cancel_gesture()
	elif event.keycode == KEY_ENTER and raising and height_adjusted:
		if commit_draft():
			set_tool("select")
	elif event.ctrl_pressed and event.keycode == KEY_S:
		save()
	elif event.ctrl_pressed and event.keycode == KEY_Z:
		redo() if event.shift_pressed else undo()
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		redo()
	elif event.ctrl_pressed and event.keycode == KEY_D:
		duplicate_selected()
	elif event.keycode == KEY_DELETE:
		delete_selected()
	elif event.keycode == KEY_F:
		focus_selected()
	elif not flying and event.keycode == KEY_G:
		set_tool("move")
	elif not flying and event.keycode == KEY_S:
		set_tool("scale")
	elif not flying and event.keycode == KEY_R:
		rotate_selected()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_update_face_visuals()
	if not flying:
		return
	var movement := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var speed := 25.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 12.0
	camera.position += camera.basis * movement.limit_length() * speed * delta


func _stop_flying() -> void:
	flying = false
	orbiting = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_stop_flying()
		if face_dragging or drawing or raising:
			_cancel_gesture()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_action("quit")


func toggle_view() -> void:
	_stop_flying()
	top_view = not top_view
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if top_view else Camera3D.PROJECTION_PERSPECTIVE
	if top_view:
		camera.position = Vector3(0, 60, 0)
		camera.rotation = Vector3(-PI / 2, 0, 0)
		camera.size = 42
	else:
		camera.position = Vector3(23, 26, 30)
		camera.look_at(Vector3.ZERO)


func focus_selected() -> void:
	var item: Dictionary = document.object_by_id(document.selected)
	if item.is_empty():
		return
	var center: Vector3 = DOC.vector3(item.position) + Vector3.UP * float(item.size[1]) * 0.5
	orbit_pivot = center
	var distance := maxf(5, DOC.vector3(item.size).length() * 1.5)
	if top_view:
		camera.position = center + Vector3.UP * 60
		camera.size = distance
	else:
		camera.position = center + camera.basis.z * distance


func duplicate_selected() -> void:
	var item: Dictionary = document.object_by_id(document.selected).duplicate(true)
	if item.is_empty() or document.data.objects.size() >= DOC.MAX_OBJECTS:
		return
	document.checkpoint()
	item.id = document.next_id()
	item.position[0] = minf(128, item.position[0] + maxf(0.5, snap_control.value))
	document.data.objects.append(item)
	document.selected = int(item.id)
	_rebuild()


func delete_selected() -> void:
	var item: Dictionary = document.object_by_id(document.selected)
	if item.is_empty():
		return
	document.checkpoint()
	document.data.objects.erase(item)
	document.selected = -1
	_rebuild()


func rotate_selected() -> void:
	if document.selected < 0:
		return
	var item: Dictionary = document.object_by_id(document.selected)
	_edit_object("yaw", wrapf(item.yaw + 90, -180, 180))


func undo() -> void:
	if moving or drawing or raising or face_dragging:
		_cancel_gesture()
	elif document.undo():
		_rebuild()


func redo() -> void:
	if not moving and not drawing and not raising and not face_dragging and document.redo():
		_rebuild()


func _commit_fields() -> void:
	_commit_name()
	for field in field_controls.values():
		# Applying every SpinBox can overwrite a programmatic/slider edit with its
		# previous, not-yet-redrawn text during a same-frame scene transition.
		if field.get_line_edit().has_focus():
			field.apply()
	get_viewport().gui_release_focus()


func save() -> void:
	_commit_fields()
	if drawing or raising or face_dragging or moving:
		status.text = "当前物体尚未完成"
		return
	if document.path.is_empty():
		_choose_save(false)
	else:
		_save_to(document.path, false)


func _choose_save(exporting: bool) -> void:
	_commit_fields()
	if drawing or raising or face_dragging or moving:
		status.text = "当前物体尚未完成"
		return
	export_only = exporting
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.title = "导出地图" if exporting else "保存地图"
	picker.current_dir = ProjectSettings.globalize_path(workspace.map_directory)
	picker.current_file = document.data.name.validate_filename() + ".lgmap"
	picker.popup_centered_ratio(0.8)


func _save_to(path: String, exporting: bool) -> bool:
	if path.get_extension().to_lower() != "lgmap":
		path += ".lgmap"
	var error := DOC.write_map(path, document.data)
	if not error.is_empty():
		status.text = error
		return false
	if not exporting:
		document.path = path
		document.mark_saved()
	_refresh_status()
	if exporting:
		status.text = "已导出：" + path
	return true


func _file_selected(path: String) -> void:
	if picker.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		_save_to(path, export_only)
	else:
		load_document(path)


func load_document(path: String) -> bool:
	var result := DOC.read_map(path)
	if result.has("error"):
		status.text = result.error
		return false
	document.data = result.data
	document.path = "" if DOC.is_builtin(path) else path
	document.selected = -1
	document.undo_stack.clear()
	document.redo_stack.clear()
	document.mark_saved()
	_cancel_gesture()
	_rebuild()
	return true


func _request_action(action: String) -> void:
	_commit_fields()
	_stop_flying()
	pending_action = action
	if document.changed() or drawing or raising:
		confirm.popup_centered()
	else:
		_perform_action()


func _perform_action() -> void:
	match pending_action:
		"new":
			_cancel_gesture()
			document.data = DOC.template()
			document.path = ""
			document.selected = -1
			document.undo_stack.clear()
			document.redo_stack.clear()
			document.mark_saved()
			_rebuild()
		"open":
			picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			picker.title = "打开地图"
			picker.current_dir = ProjectSettings.globalize_path(workspace.map_directory)
			picker.popup_centered_ratio(0.8)
		"training":
			_store_view()
			if document.changed() and not document.saved_text.is_empty():
				document.data = JSON.parse_string(document.saved_text)
				document.undo_stack.clear()
				document.redo_stack.clear()
				document.selected = -1
			workspace.default_training()
		"quit":
			get_tree().quit()


func _store_view() -> void:
	workspace.editor_view = {"position": camera.position, "rotation": camera.rotation,
		"top_view": top_view, "size": camera.size, "pivot": orbit_pivot}


func play() -> void:
	_commit_fields()
	if drawing or raising or face_dragging or moving:
		status.text = "当前物体尚未完成"
		return
	var error := DOC.validate(document.data)
	if not error.is_empty():
		status.text = error
		return
	_store_view()
	_stop_flying()
	workspace.play_map(document.data, document.path, true)
