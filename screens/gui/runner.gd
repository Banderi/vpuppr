extends BaseTreeLayout

var _selectable_gui_count: int = 0

#-----------------------------------------------------------------------------#
# Builtin functions                                                           #
#-----------------------------------------------------------------------------#

func _init() -> void:
	pass

func _setup_logger() -> void:
	logger = Logger.new(self)

var first_runner = false
func _setup() -> Result:
	_selectable_gui_count = _get_selectable_gui_count()

	var default_runner := _create_view({
		"name": Globals.DEFAULT_RUNNER_PATH.get_file().get_basename().capitalize(),
		"run_args": [
			Globals.DEFAULT_RUNNER_PATH
		]
	})

	_initial_page = default_runner.name.capitalize()
	add_child(default_runner)

	for ext in AM.em.query_extensions_for_tag(Globals.ExtensionTypes.RUNNER):
		ext = ext as Extension.ExtensionResource
		var view := _create_view({
			"name": tr(ext.translation_key),
			"run_args": [
				ext.entrypoint
			]
		})

		# run VRM immediately
		if !first_runner:
			call_deferred("_on_run", ext.entrypoint, null)
			first_runner = true
		add_child(view)
	
	return ._setup()

func _post_setup() -> Result:
	if get_child_count() > 2:
		var default_runner: Control = get_child(1)
		default_runner.hide()

		var next_runner: Control = get_child(2)
		_initial_page = next_runner.name

		var res := Safely.wrap(_clear_tree())
		if res.is_err():
			return res
		
		res = Safely.wrap(_build_tree(PoolStringArray([default_runner.name])))
		if res.is_err():
			return res

	return Safely.ok()

#-----------------------------------------------------------------------------#
# Connections                                                                 #
#-----------------------------------------------------------------------------#

func _on_run(path: String, toggle: CheckButton) -> void:
	if toggle != null && toggle.pressed:
		var popup := _create_gui_select(path)

		add_child(popup)
		popup.popup_centered_ratio()
	else:
		_run_runner(path, Globals.DEFAULT_GUI_PATH)

func _on_gui_selected(runner_path: String, gui_path: String) -> void:
	var file := File.new()
	if not file.file_exists(gui_path):
		logger.error("Gui doesn't exist at path %s" % gui_path)
		return
	
	_run_runner(runner_path, gui_path)

func _terminate(node: Node) -> void:
	node.queue_free()

#-----------------------------------------------------------------------------#
# Private functions                                                           #
#-----------------------------------------------------------------------------#

static func _get_selectable_gui_count() -> int:
	var r: int = 1

	for ext in AM.em.query_extensions_for_tag(Globals.ExtensionTypes.GUI):
		# TODO this might not be a great solution
		if not ext.extra.get(Globals.ExtensionExtraKeys.SELECTABLE_GUI, false):
			continue

		r += 1

	return r

func _create_view(data: Dictionary) -> ScrollContainer:
	var sc := ScrollContainer.new()
	ControlUtil.h_expand_fill(sc)
	sc.name = data.name
	sc.scroll_horizontal_enabled = false

	var list := VBoxContainer.new()
	ControlUtil.h_expand_fill(list)
	ControlUtil.v_expand_fill(list)

	sc.add_child(list)

	var title := Label.new()
	ControlUtil.h_expand_fill(title)
	title.align = Label.ALIGN_CENTER
	title.text = data.name

	list.add_child(title)

	var preview := TextureRect.new()
	ControlUtil.h_expand_fill(preview)
	ControlUtil.v_expand_fill(preview)
	preview.expand = true
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT

	var preview_image_res: Result = _find_runner_preview(data.name)
	if not preview_image_res or preview_image_res.is_err():
		preview.texture = load("res://assets/NoPreview.png")
	else:
		var image_texture := ImageTexture.new()
		image_texture.create_from_image(preview_image_res.unwrap())
		preview.texture = image_texture
	preview.modulate = Color(0.5,0.5,0.5,0.5)
	list.add_child(preview)

	var select_gui_toggle := CheckButton.new()
	select_gui_toggle.text = tr("DEFAULT_GUI_LANDING_SCREEN_RUNNER_SHOW_GUI_SELECTOR")
	select_gui_toggle.set_pressed_no_signal(true if _selectable_gui_count > 1 else false)

	list.add_child(select_gui_toggle)

	data.run_args.append(select_gui_toggle)

	var run_button := Button.new()
	run_button.text = tr("DEFAULT_GUI_LANDING_SCREEN_RUNNER_RUN")
	
	run_button.connect("pressed", self, "_on_run", data.run_args)

	list.add_child(run_button)

	return sc

func _find_runner_preview(view_name: String) -> Result:
	var expected_path := "%s/%s.%s" % [
		Globals.RUNNER_PREVIEW_DIR_PATH,
		view_name,
		Globals.RUNNER_PREVIEW_FILE_EXT
	]

	var file := File.new()

	if file.file_exists(expected_path):
		var image := Image.new()
		if image.load(expected_path) != OK:
			return Safely.err(Error.Code.RUNNER_NO_PREVIEW_IMAGE_FOUND, expected_path)
		return Safely.ok(image)

	return Safely.err(Error.Code.RUNNER_NO_PREVIEW_IMAGE_FOUND, expected_path)

func _create_gui_select(runner_path: String) -> WindowDialog:
	var wd := WindowDialog.new()

	var pc := PanelContainer.new()
	ControlUtil.all_expand_fill(pc)
	pc.anchor_bottom = 1.0
	pc.anchor_right = 1.0

	wd.add_child(pc)

	var sc := ScrollContainer.new()
	
	pc.add_child(sc)

	var list := VBoxContainer.new()
	ControlUtil.all_expand_fill(list)

	sc.add_child(list)

	for i in ["popup_hide", "hide"]:
		wd.connect(i, self, "_terminate", [wd])

	var default_gui := Button.new()
	default_gui.text = tr("DEFAULT_GUI_LANDING_SCREEN_RUNNER_DEFAULT_GUI_NAME")
	default_gui.connect("pressed", self, "_on_gui_selected", [runner_path, Globals.DEFAULT_GUI_PATH])

	list.add_child(default_gui)

	for ext in AM.em.query_extensions_for_tag(Globals.ExtensionTypes.GUI):
		# TODO this might not be a great solution
		if not ext.extra.get(Globals.ExtensionExtraKeys.SELECTABLE_GUI, false):
			continue

		var button := Button.new()
		button.text = ext.resource_name.capitalize()
		button.connect("pressed", self, "_on_gui_selected", [ext.resource_entrypoint])

		list.add_child(button)

	return wd

func _run_runner(runner_path: String, gui_path: String) -> void:
	var res: Result = Safely.wrap(FileUtil.switch_to_runner(runner_path, gui_path))

	if res.is_err():
		logger.error(res)

#-----------------------------------------------------------------------------#
# Public functions                                                            #
#-----------------------------------------------------------------------------#
