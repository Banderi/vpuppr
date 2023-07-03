class_name DefaultGui
extends Control

enum SidebarButtons {
	NONE = 0,
	
	MODEL,
	BONES,
	TRACKING,
	PROPS,
	PRESETS
}

const Model = preload("res://screens/gui/menus/model.tscn")
const Bones = preload("res://screens/gui/menus/bones.tscn")
const Tracking = preload("res://screens/gui/menus/tracking.tscn")
const BlendShapes = preload("res://screens/gui/menus/blend-shapes/blend_shapes.tscn")
const Presets = preload("res://screens/gui/menus/presets.tscn")

const BUILTIN_MENUS := {
	"DEFAULT_GUI_MODEL": Model,
	"DEFAULT_GUI_BONES": Bones,
	"DEFAULT_GUI_TRACKING": Tracking,
	"DEFAULT_GUI_BLEND_SHAPES": BlendShapes,
	"DEFAULT_GUI_PRESETS": Presets
}

var logger: Logger
onready var menu_bar: MenuBar = $VBoxContainer/MenuBar

#-----------------------------------------------------------------------------#
# Builtin functions                                                           #
#-----------------------------------------------------------------------------#

func _init() -> void:
	logger = Logger.new("DefaultGui")

func _ready() -> void:
	menu_bar.parent = self

	var menu_list := $VBoxContainer/Runner/PanelContainer/PanelContainer/ScrollContainer/MenuList as VBoxContainer

	for menu_name in BUILTIN_MENUS.keys():
		var button := Button.new()
		button.text = tr(menu_name)
		button.connect("pressed", self, "_on_pressed", [BUILTIN_MENUS[menu_name], tr(menu_name)])

		menu_list.add_child(button)

	for ext in AM.em.query_extensions_for_tag(Globals.ExtensionTypes.GUI):
		if not ext.extra.get(Globals.ExtensionExtraKeys.CAN_POPUP, false):
			continue
		
		var button := Button.new()
		button.text = tr(ext.translation_key)
		button.connect("pressed", self, "_on_pressed", [load(ext.entrypoint), tr(ext.translation_key)])

		menu_list.add_child(button)
	
	# TODO: localization
	$VBoxContainer/Runner/ControlsList.text = str(
#		"\n",tr("NOTIFICATION_PRESS_ESCAPE_TO_HIDE_GUI"),
#		"\n",tr("NOTIFICATION_PRESS_SPACE_TO_CALIBRATE")
		"Escape: hide GUI\n",
		"Shift + Escape: quit runner\n",
		"Spacebar: recalibrate tracking\n",
#		"Spacebar: recalibrate tracking\n",
		""
	)

func _input(event: InputEvent) -> void:
#	if event.is_action_pressed("back_to_main_menu"):
#		get_tree().change_scene(Globals.LANDING_SCREEN_PATH)
	if event.is_action_pressed("toggle_gui"):
		visible = not visible
		
		for child in get_children():
			child.visible = visible

#-----------------------------------------------------------------------------#
# Connections                                                                 #
#-----------------------------------------------------------------------------#

func _set_mouse_input_propagation_recursive(n, mode):
	for c in n.get_children():
		if c is Control:
			(c as Control).mouse_filter = mode
			_set_mouse_input_propagation_recursive(c, mode)

func _on_pressed(scene, popup_name: String) -> void:
	var popup: WindowDialog

	var res := Safely.wrap(AM.tcm.pull(popup_name))
	if res.is_err():
		if res.unwrap_err().code != Error.Code.TEMP_CACHE_MANAGER_KEY_NOT_FOUND:
			logger.error(res)
			return
		popup = BasePopup.new(scene, popup_name)

		AM.tcm.push(popup_name, popup).cleanup_on_signal(popup, "tree_exiting")

		add_child(popup)
		_set_mouse_input_propagation_recursive(popup, MOUSE_FILTER_PASS)
	else:
		popup = res.unwrap()
		move_child(popup, get_child_count() - 1)

func _on_popup_clicked(event: InputEvent, popup: Control) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	move_child(popup, get_child_count() - 1)

#-----------------------------------------------------------------------------#
# Private functions                                                           #
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions                                                            #
#-----------------------------------------------------------------------------#

func add_child(node: Node, legible_unique_name: bool = false) -> void:
	.add_child(node, legible_unique_name)
	if node is BasePopup:
		(node as BasePopup).connect("gui_input", self, "_on_popup_clicked", [node])
