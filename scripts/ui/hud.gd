extends CanvasLayer

## HUD minimo: minimapa en la esquina superior derecha, brujula encima, y el nombre de
## Rito arriba a la izquierda. Todo 2D, asi que no toca el coste de relleno del terreno.

const MinimapScript := preload("res://scripts/ui/minimap.gd")
const WeaponScript := preload("res://scripts/combat/weapon.gd")

const COMPASS_WIDTH := 220.0
const COMPASS_HEIGHT := 30.0
const VISIBLE_ARC := PI * 0.42
const CARDINALS: Array[Dictionary] = [
	{"label": "N", "angle": 0.0},
	{"label": "E", "angle": PI * 0.5},
	{"label": "S", "angle": PI},
	{"label": "O", "angle": PI * 1.5},
]

## Fila de armas abajo a la derecha: el arsenal siempre visible, sin abrir el menu.
## Va a la derecha porque la pantalla de arranque ocupa la franja izquierda durante los
## primeros segundos, y el solape de dos textos se lee como un fallo.
const CHIP_WIDTH := 128.0
const CHIP_HEIGHT := 24.0
const CHIP_GAP := 6.0
const CHIP_TOP := 596.0
const RIGHT_MARGIN := 18.0
const VIEW_WIDTH := 1280.0

## Distancia a la que aparece la barra de vida del jefe.
const BOSS_BAR_RANGE := 45.0

const ACCENT := Color(0.95, 0.88, 0.70)
const TEXT := Color(0.88, 0.84, 0.74)
const DIM := Color(0.68, 0.64, 0.56)

var _player: Node3D
var _minimap: Control
var _compass_labels: Array[Label] = []
var _compass_center: Vector2
var _health_fill: ColorRect
var _kills_label: Label
var _chip_backgrounds: Array[ColorRect] = []
var _chip_labels: Array[Label] = []
var _weapon_name_label: Label
var _weapon_stats_label: Label
var _combat_node: Node
var _progression: Node
var _objective_label: Label
var _coins_label: Label
var _panis_label: Label
var _victory_label: Label
var _combo_label: Label
var _guard_fill: ColorRect
var _parry_label: Label
var _parry_tween: Tween
var _riposte_label: Label
var _xp_fill: ColorRect
var _xp_level_label: Label
var _mission_label: Label
var _streak_label: Label
var _mission_system: Node
var _mission_system_bound := false
var _active_mission: Dictionary = {}
var _mission_current := 0
var _mission_goal := 0
var _xp_ratio := 0.0
var _boss: Node3D
var _boss_label: Label
var _boss_bar: Control
var _boss_bar_fill: ColorRect
var _boss_won := false
var _banner_until := 0.0


func setup(player: Node3D, terrain: Terrain3D, center: Vector3, combat: Node,
		progression: Node = null, boss: Node3D = null) -> void:
	_player = player
	_progression = progression
	_boss = boss
	layer = 5

	var name_label := Label.new()
	name_label.text = "RITO"
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.position = Vector2(18, 14)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)

	_build_compass()

	_minimap = MinimapScript.new()
	_minimap.position = Vector2(1280 - 168, 22)
	add_child(_minimap)
	_minimap.call("setup", player, terrain, center)

	var combatant := player.get_node_or_null("Combatant")
	if combatant != null:
		_build_health(combatant, combat)

	_build_guard(player)
	_build_defense_labels()
	_build_combo_label()
	_build_arsenal(combat)
	if progression != null:
		_build_objective(progression)
	if boss != null:
		_build_boss_bar(boss)


## La fila de armas: tres fichas con el nombre corto y la activa resaltada. El nombre
## completo y las cifras de la activa van debajo, que es lo que se consulta al pelear.
## El cartel del combo: aparece en el segundo golpe de la cadena y se apaga solo.
## Sin el, el jugador no sabe que esta encadenando.
## Barra fina bajo la vida: se vacia al bloquear y se rellena al soltar la guardia.
func _build_guard(player: Node) -> void:
	var background := ColorRect.new()
	background.color = Color(0.06, 0.05, 0.04, 0.55)
	background.size = Vector2(190, 6)
	background.position = Vector2(18, 58)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_guard_fill = ColorRect.new()
	_guard_fill.color = Color(0.42, 0.62, 0.78)
	_guard_fill.size = Vector2(186, 4)
	_guard_fill.position = Vector2(20, 59)
	_guard_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_guard_fill)

	if player.has_signal("guard_changed"):
		player.connect("guard_changed", Callable(self, "_on_guard_changed"))
	if player.has_signal("riposte_changed"):
		player.connect("riposte_changed", Callable(self, "_on_riposte_changed"))
	if player.has_signal("parried"):
		player.connect("parried", Callable(self, "_on_parried"))


func _build_defense_labels() -> void:
	_parry_label = Label.new()
	_parry_label.text = "PARRY"
	_parry_label.add_theme_font_size_override("font_size", 30)
	_parry_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.30))
	_parry_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_parry_label.add_theme_constant_override("shadow_offset_x", 2)
	_parry_label.add_theme_constant_override("shadow_offset_y", 2)
	_parry_label.position = Vector2(640.0 - 80.0, 112.0)
	_parry_label.size = Vector2(160, 36)
	_parry_label.pivot_offset = _parry_label.size * 0.5
	_parry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_parry_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parry_label.visible = false
	add_child(_parry_label)

	_riposte_label = Label.new()
	_riposte_label.text = "CONTRAATAQUE"
	_riposte_label.add_theme_font_size_override("font_size", 17)
	_riposte_label.add_theme_color_override("font_color", Color(1.0, 0.74, 0.22))
	_riposte_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_riposte_label.add_theme_constant_override("shadow_offset_x", 1)
	_riposte_label.add_theme_constant_override("shadow_offset_y", 1)
	_riposte_label.position = Vector2(640.0 - 120.0, 148.0)
	_riposte_label.size = Vector2(240, 24)
	_riposte_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_riposte_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_riposte_label.visible = false
	add_child(_riposte_label)


func _on_guard_changed(current: float, maximum: float) -> void:
	if _guard_fill == null:
		return
	_guard_fill.size.x = 186.0 * clampf(current / maxf(maximum, 1.0), 0.0, 1.0)


func _on_parried() -> void:
	if _parry_label == null:
		return
	if _parry_tween != null and _parry_tween.is_valid():
		_parry_tween.kill()
	_parry_label.visible = true
	_parry_label.modulate.a = 1.0
	_parry_label.scale = Vector2.ONE * 1.3
	_parry_tween = create_tween()
	_parry_tween.set_parallel(true)
	_parry_tween.tween_property(_parry_label, "scale", Vector2.ONE, 0.12)
	_parry_tween.tween_property(_parry_label, "modulate:a", 0.0, 0.45).set_delay(0.15)
	_parry_tween.finished.connect(_parry_label.hide)


func _on_riposte_changed(active: bool) -> void:
	if _riposte_label != null:
		_riposte_label.visible = active


func _build_combo_label() -> void:
	_combo_label = Label.new()
	_combo_label.add_theme_font_size_override("font_size", 30)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.74, 0.22))
	_combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_combo_label.add_theme_constant_override("shadow_offset_x", 2)
	_combo_label.add_theme_constant_override("shadow_offset_y", 2)
	_combo_label.position = Vector2(640.0 - 70.0, 92.0)
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_label.visible = false
	add_child(_combo_label)


func _on_combo_changed(step: int) -> void:
	if _combo_label == null:
		return
	if step <= 1:
		_combo_label.visible = false
		return
	_combo_label.text = "COMBO x%d" % step
	_combo_label.visible = true
	_combo_label.modulate.a = 1.0
	_combo_label.scale = Vector2.ONE * 1.25
	var tween := create_tween()
	tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.15)
	tween.tween_interval(0.5)
	tween.tween_property(_combo_label, "modulate:a", 0.0, 0.35)


func _build_arsenal(combat: Node) -> void:
	if combat != null and combat.has_signal("combo_changed"):
		combat.connect("combo_changed", Callable(self, "_on_combo_changed"))
	_combat_node = combat
	var count := WeaponScript.count()
	var row_width := float(count) * CHIP_WIDTH + float(count - 1) * CHIP_GAP
	var row_left := VIEW_WIDTH - RIGHT_MARGIN - row_width

	for i in count:
		var weapon: Dictionary = WeaponScript.get_weapon(i)

		var chip := ColorRect.new()
		chip.position = Vector2(row_left + float(i) * (CHIP_WIDTH + CHIP_GAP), CHIP_TOP)
		chip.size = Vector2(CHIP_WIDTH, CHIP_HEIGHT)
		chip.color = Color(0.10, 0.09, 0.07, 0.6)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(chip)

		var label := Label.new()
		label.text = "%d  %s" % [i + 1, str(weapon["name"])]
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", TEXT)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.position = chip.position + Vector2(8, 3)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)

		_chip_backgrounds.append(chip)
		_chip_labels.append(label)

	_weapon_name_label = _make_right_label(21, ACCENT)
	_weapon_name_label.position = Vector2(VIEW_WIDTH - RIGHT_MARGIN - 260.0, CHIP_TOP + 32)
	_weapon_name_label.size = Vector2(260, 28)
	add_child(_weapon_name_label)

	_weapon_stats_label = _make_right_label(14, TEXT)
	_weapon_stats_label.position = Vector2(VIEW_WIDTH - RIGHT_MARGIN - 360.0, CHIP_TOP + 62)
	_weapon_stats_label.size = Vector2(360, 20)
	add_child(_weapon_stats_label)

	var hint := _make_right_label(13, DIM)
	hint.text = "B: arsenal · C: silbar"
	hint.position = Vector2(VIEW_WIDTH - RIGHT_MARGIN - 200.0, CHIP_TOP + 84)
	hint.size = Vector2(200, 20)
	add_child(hint)

	if combat != null and combat.has_signal("weapon_selected"):
		combat.connect("weapon_selected", Callable(self, "_on_weapon_selected"))
	_refresh_arsenal(combat)


func _make_right_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _on_weapon_selected(_index: int) -> void:
	var combat := _combat_node
	if combat != null:
		_refresh_arsenal(combat)


func _refresh_arsenal(combat: Node) -> void:
	if combat == null:
		return
	var current := int(combat.get("weapon_index"))
	var weapon: Dictionary = WeaponScript.get_weapon(current)
	for i in _chip_backgrounds.size():
		var equipped := (i == current)
		_chip_backgrounds[i].color = Color(0.24, 0.19, 0.12, 0.85) if equipped else Color(0.10, 0.09, 0.07, 0.6)
		_chip_labels[i].add_theme_color_override("font_color", ACCENT if equipped else TEXT)

	var reach := float(weapon["reach"])
	var reach_text := ""
	if str(weapon["mode"]) == WeaponScript.MODE_THROW:
		reach_text = "%s m de vuelo" % _decimal(reach, 0)
	else:
		reach_text = "%s m" % _decimal(reach, 1)
	_weapon_name_label.text = str(weapon["name"]).to_upper()
	_weapon_stats_label.text = "Daño %d  ·  Alcance %s  ·  Cadencia %s s" % [
		int(weapon["damage"]), reach_text, _decimal(float(weapon["cooldown"]), 2)]


## Los decimales en español llevan coma. El juego esta en castellano, asi que las cifras
## que lee el jugador tambien.
func _decimal(value: float, decimals: int) -> String:
	return String.num(value, decimals).replace(".", ",")


func _build_health(combatant: Combatant, combat: Node) -> void:
	var background := ColorRect.new()
	background.color = Color(0.06, 0.05, 0.04, 0.55)
	background.size = Vector2(190, 14)
	background.position = Vector2(18, 44)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_health_fill = ColorRect.new()
	_health_fill.color = Color(0.72, 0.24, 0.20)
	_health_fill.size = Vector2(186, 10)
	_health_fill.position = Vector2(20, 46)
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_health_fill)

	_kills_label = Label.new()
	_kills_label.text = "Bajas: 0"
	_kills_label.add_theme_font_size_override("font_size", 15)
	_kills_label.add_theme_color_override("font_color", Color(0.90, 0.84, 0.70))
	_kills_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_kills_label.add_theme_constant_override("shadow_offset_x", 1)
	_kills_label.add_theme_constant_override("shadow_offset_y", 1)
	_kills_label.position = Vector2(18, 80)
	_kills_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kills_label)

	combatant.health_changed.connect(_on_health_changed)
	if combat != null:
		combat.kill_count_changed.connect(_on_kills_changed)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_fill.size.x = 186.0 * clampf(current / maxf(maximum, 1.0), 0.0, 1.0)


func _on_kills_changed(count: int) -> void:
	_kills_label.text = "Bajas: %d" % count


## Objetivo de la partida, denarios e inventario, con cartel de victoria a las 6 bajas.
func _build_objective(progression: Node) -> void:
	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 15)
	_objective_label.add_theme_color_override("font_color", ACCENT)
	_objective_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_objective_label.add_theme_constant_override("shadow_offset_x", 1)
	_objective_label.add_theme_constant_override("shadow_offset_y", 1)
	_objective_label.position = Vector2(18, 98)
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_objective_label)

	if _coins_label == null:
		_coins_label = Label.new()
		_coins_label.add_theme_font_size_override("font_size", 14)
		_coins_label.add_theme_color_override("font_color", Color(0.95, 0.80, 0.25))
		_coins_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		_coins_label.add_theme_constant_override("shadow_offset_x", 1)
		_coins_label.add_theme_constant_override("shadow_offset_y", 1)
		_coins_label.position = Vector2(18, 116)
		_coins_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_coins_label)

	_panis_label = Label.new()
	_panis_label.add_theme_font_size_override("font_size", 14)
	_panis_label.add_theme_color_override("font_color", DIM)
	_panis_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_panis_label.add_theme_constant_override("shadow_offset_x", 1)
	_panis_label.add_theme_constant_override("shadow_offset_y", 1)
	_panis_label.position = Vector2(18, 134)
	_panis_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panis_label)

	_boss_label = Label.new()
	_boss_label.add_theme_font_size_override("font_size", 14)
	_boss_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.30))
	_boss_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_boss_label.add_theme_constant_override("shadow_offset_x", 1)
	_boss_label.add_theme_constant_override("shadow_offset_y", 1)
	_boss_label.position = Vector2(18, 152)
	_boss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_label)

	_victory_label = Label.new()
	_victory_label.text = "¡VICTORIA! 6 bandidos eliminados"
	_victory_label.add_theme_font_size_override("font_size", 38)
	_victory_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.40))
	_victory_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_victory_label.add_theme_constant_override("shadow_offset_x", 2)
	_victory_label.add_theme_constant_override("shadow_offset_y", 2)
	_victory_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_victory_label.visible = false
	_victory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_victory_label)

	progression.connect("mission_changed", Callable(self, "_on_mission_changed"))
	progression.connect("mission_completed", Callable(self, "_on_victory"))
	progression.connect("coins_changed", Callable(self, "_on_coins"))
	progression.connect("inventory_changed", Callable(self, "_on_inventory"))
	progression.connect("boss_progress_changed", Callable(self, "_on_boss_progress"))
	var tracker = progression.get("tracker")
	_on_mission_changed(int(tracker.get("kills")), int(tracker.get("goal")))
	_on_coins(int(progression.get("coins")))
	_on_inventory()
	_on_boss_progress(0, 1)


func _on_mission_changed(kills: int, goal: int) -> void:
	if _mission_system_bound:
		return
	if _objective_label != null:
		_objective_label.text = "Bandidos: %d/%d" % [kills, goal]


func _on_coins(coins: int) -> void:
	if _coins_label != null:
		_coins_label.text = "Denarios: %d" % coins


func _on_inventory() -> void:
	if _panis_label == null:
		return
	# El panis del HUD va desde MissionSystem (pool jugable) cuando esta enlazado;
	# sin el, se cae al pool legado de Progression.
	var panis := 0
	var inventario: Variant = null
	if _mission_system != null:
		inventario = _mission_system.get("inventory")
	if inventario != null and (inventario as Object).has_method("count"):
		panis = int((inventario as Object).call("count", "panis"))
	elif _progression != null:
		panis = int(_progression.call("panis_count"))
	else:
		return
	_panis_label.text = "Panis: %d · E: comer" % panis


func _on_victory() -> void:
	# El tracker legado de Progression cuenta CUALQUIER baja: con MissionSystem
	# enlazado ese cartel seria una victoria falsa y permanente a las 6 bajas.
	if _mission_system_bound:
		return
	if _victory_label != null:
		if not _boss_won:
			_victory_label.text = "¡VICTORIA! 6 bandidos eliminados"
		_victory_label.visible = true
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_local", "kill", -4.0)


## Barra de vida del Praetorian: solo sale cuando el jefe esta cerca. Saber que hay
## un jefe al fondo de la cueva antes de llegar seria hacer trampas.
func _build_boss_bar(boss: Node3D) -> void:
	_boss = boss
	var bar := Control.new()
	bar.position = Vector2(640.0 - 180.0, 62.0)
	bar.size = Vector2(360.0, 18.0)
	bar.visible = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var background := ColorRect.new()
	background.color = Color(0.06, 0.05, 0.04, 0.6)
	background.size = Vector2(360.0, 18.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(background)

	_boss_bar_fill = ColorRect.new()
	_boss_bar_fill.color = Color(0.62, 0.16, 0.14)
	_boss_bar_fill.size = Vector2(356.0, 14.0)
	_boss_bar_fill.position = Vector2(2.0, 2.0)
	_boss_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_boss_bar_fill)

	_boss_bar = bar
	var combatant = boss.get_node_or_null("Combatant")
	if combatant != null:
		combatant.health_changed.connect(_on_boss_health)
	if boss.has_signal("boss_defeated"):
		boss.connect("boss_defeated", Callable(self, "_on_boss_defeated"))


func _on_boss_health(current: float, maximum: float) -> void:
	if _boss_bar_fill != null:
		_boss_bar_fill.size.x = 356.0 * clampf(current / maxf(maximum, 1.0), 0.0, 1.0)


func _on_boss_defeated() -> void:
	_boss_won = true
	if _boss_bar != null:
		_boss_bar.visible = false
	if _victory_label != null:
		_victory_label.text = "¡RITO COMPLETO!  Praetorian derrotado"
		_victory_label.visible = true


func _on_boss_progress(kills: int, goal: int) -> void:
	if _boss_label != null:
		_boss_label.text = "Praetorian: %d/%d" % [kills, goal]


## Enlaza el MissionSystem: XP, nivel, denarios y tracker de mision.
## La barra de XP va bajo la barra de vida (fondo en y 60) y la etiqueta
## "Nv N" a su derecha; el tracker va al pie de la columna de Rito (y 164)
## para no solapar objetivo, denarios, panis ni jefe. Los denarios reutilizan
## _coins_label (el de Progression) para no duplicar la etiqueta. Todo se
## actualiza solo por senal, sin sondeo en _process.
func bind_mission_system(system: Node) -> void:
	if system == null or _mission_system_bound:
		return
	_mission_system_bound = true
	_mission_system = system
	if _objective_label != null:
		_objective_label.visible = false
	_ensure_mission_widgets()
	system.connect("xp_changed", Callable(self, "_on_xp_changed"))
	system.connect("coins_changed", Callable(self, "_on_coins"))
	system.connect("inventory_changed", Callable(self, "_on_inventory"))
	system.connect("mission_started", Callable(self, "_on_mission_started"))
	system.connect("mission_progress", Callable(self, "_on_mission_progress"))
	system.connect("mission_completed", Callable(self, "_on_mission_completed"))
	system.connect("mission_failed", Callable(self, "_on_mission_ended"))
	system.connect("mission_abandoned", Callable(self, "_on_mission_ended"))
	system.connect("streak_changed", Callable(self, "_on_streak_changed"))


func _on_streak_changed(current: int, best: int) -> void:
	if _streak_label != null:
		_streak_label.text = "Racha: %d · Mejor: %d" % [current, best]


## Crea los controles de mision si faltan (tambien sin setup previo, para que
## el arnes pueda enlazar sin terreno ni jugador).
func _ensure_mission_widgets() -> void:
	if _xp_fill == null:
		var fondo := ColorRect.new()
		fondo.color = Color(0.06, 0.05, 0.04, 0.55)
		fondo.size = Vector2(190, 6)
		fondo.position = Vector2(18, 66)
		fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fondo)
		_xp_fill = ColorRect.new()
		_xp_fill.color = Color(0.95, 0.75, 0.25, 0.75)
		_xp_fill.size = Vector2(0, 4)
		_xp_fill.position = Vector2(20, 67)
		_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_xp_fill)
		_xp_level_label = Label.new()
		_xp_level_label.text = "Nv 1"
		_xp_level_label.add_theme_font_size_override("font_size", 13)
		_xp_level_label.add_theme_color_override("font_color", ACCENT)
		_xp_level_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		_xp_level_label.add_theme_constant_override("shadow_offset_x", 1)
		_xp_level_label.add_theme_constant_override("shadow_offset_y", 1)
		_xp_level_label.position = Vector2(214, 64)
		_xp_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_xp_level_label)
	if _coins_label == null:
		_coins_label = Label.new()
		_coins_label.add_theme_font_size_override("font_size", 14)
		_coins_label.add_theme_color_override("font_color", Color(0.95, 0.80, 0.25))
		_coins_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		_coins_label.add_theme_constant_override("shadow_offset_x", 1)
		_coins_label.add_theme_constant_override("shadow_offset_y", 1)
		_coins_label.position = Vector2(18, 116)
		_coins_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_coins_label)
	if _mission_label == null:
		_mission_label = Label.new()
		_mission_label.add_theme_font_size_override("font_size", 14)
		_mission_label.add_theme_color_override("font_color", ACCENT)
		_mission_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		_mission_label.add_theme_constant_override("shadow_offset_x", 1)
		_mission_label.add_theme_constant_override("shadow_offset_y", 1)
		_mission_label.position = Vector2(18, 174)
		_mission_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_mission_label)
	if _streak_label == null:
		_streak_label = Label.new()
		_streak_label.text = "Racha: 0 · Mejor: 0"
		_streak_label.add_theme_font_size_override("font_size", 14)
		_streak_label.add_theme_color_override("font_color", DIM)
		_streak_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		_streak_label.add_theme_constant_override("shadow_offset_x", 1)
		_streak_label.add_theme_constant_override("shadow_offset_y", 1)
		_streak_label.position = Vector2(18, 192)
		_streak_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_streak_label)


func _on_xp_changed(total: int, needed: int, level: int) -> void:
	if _xp_level_label != null:
		_xp_level_label.text = "Nv %d" % level
	var ratio: float
	if needed <= 0:
		ratio = 1.0
	else:
		ratio = clampf(float(total) / float(needed), 0.0, 1.0)
	_xp_ratio = ratio
	if _xp_fill != null:
		_xp_fill.size.x = 186.0 * ratio


func _on_mission_started(mission: Dictionary) -> void:
	_active_mission = mission.duplicate(true)
	_mission_current = int(mission.get("kills_done", 0))
	_mission_goal = int(mission.get("targets", 0))
	_refresh_mission_label()


func _on_mission_progress(current: int, goal: int) -> void:
	_mission_current = current
	_mission_goal = goal
	_refresh_mission_label()


func _on_mission_completed(_mission: Dictionary, _rewards: Dictionary) -> void:
	_clear_mission_label()
	if _boss_won or _victory_label == null:
		return
	_victory_label.text = "Misión completada"
	_victory_label.visible = true
	_banner_until = float(Time.get_ticks_msec()) / 1000.0 + 2.5


func _on_mission_ended(_mission: Dictionary) -> void:
	_clear_mission_label()


func _clear_mission_label() -> void:
	_active_mission = {}
	_mission_current = 0
	_mission_goal = 0
	if _mission_label != null:
		_mission_label.text = ""


func _refresh_mission_label() -> void:
	if _mission_label == null or _active_mission.is_empty():
		return
	var tipo := str(_active_mission.get("type", ""))
	if tipo == "defense":
		_mission_label.text = "Oleada %d/3" % _defense_wave(_mission_current)
	else:
		_mission_label.text = "Bandidos restantes: %d" % maxi(_mission_goal - _mission_current, 0)


## Oleada de la defensa a partir de las bajas totales: 0-3 la primera,
## 4-9 la segunda (4+6) y desde 10 la tercera (4+6+8 = 18). El techo de
## defensa son 3 oleadas, asi que 17 o 18 bajas siguen en la tercera.
func _defense_wave(kills: int) -> int:
	if kills < 4:
		return 1
	if kills < 10:
		return 2
	return 3


## Solo lectura para el arnes: el texto visible y el relleno de la barra.
func xp_label_text() -> String:
	if _xp_level_label == null:
		return ""
	return _xp_level_label.text


func coins_label_text() -> String:
	if _coins_label == null:
		return ""
	return _coins_label.text


func mission_label_text() -> String:
	if _mission_label == null:
		return ""
	return _mission_label.text


func streak_label_text() -> String:
	if _streak_label == null:
		return ""
	return _streak_label.text


func xp_fill_ratio() -> float:
	return _xp_ratio


func _update_boss_bar_visibility() -> void:
	if _boss_bar == null or _boss == null or _player == null:
		return
	var alive := true
	var combatant = _boss.get_node_or_null("Combatant")
	if combatant != null:
		alive = bool(combatant.call("is_alive"))
	var cerca := _player.global_position.distance_to(_boss.global_position) < BOSS_BAR_RANGE
	_boss_bar.visible = alive and cerca


func _build_compass() -> void:
	var root := Control.new()
	root.size = Vector2(COMPASS_WIDTH, COMPASS_HEIGHT)
	root.position = Vector2((1280 - COMPASS_WIDTH) * 0.5, 18)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var background := ColorRect.new()
	background.color = Color(0.06, 0.05, 0.04, 0.35)
	background.size = Vector2(COMPASS_WIDTH, COMPASS_HEIGHT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)

	_compass_center = Vector2(COMPASS_WIDTH * 0.5, COMPASS_HEIGHT * 0.5)
	for cardinal in CARDINALS:
		var label := Label.new()
		label.text = cardinal["label"]
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(label)
		_compass_labels.append(label)


func _process(_delta: float) -> void:
	if _banner_until > 0.0 and float(Time.get_ticks_msec()) / 1000.0 >= _banner_until:
		_banner_until = 0.0
		if _victory_label != null and not _boss_won:
			_victory_label.visible = false
	_update_boss_bar_visibility()
	if _player == null or _compass_labels.is_empty():
		return
	var yaw: Node3D = _player.get("camera_yaw")
	if yaw == null:
		return
	var view := wrapf(float(yaw.rotation.y), -PI, PI)
	for i in _compass_labels.size():
		var cardinal: Dictionary = CARDINALS[i]
		var label := _compass_labels[i]
		# Angulo relativo envuelto a [-PI, PI): sin esto N y S caen en el mismo punto
		# de la barra y se solapan cuando la camara mira al norte.
		var relative := wrapf(float(cardinal["angle"]) - view, -PI, PI)
		if absf(relative) > VISIBLE_ARC:
			label.visible = false
			continue
		label.visible = true
		label.position = _compass_center + Vector2(
			(relative / VISIBLE_ARC) * (COMPASS_WIDTH * 0.5 - 18.0), -6.0)
		label.modulate.a = 1.0 - pow(absf(relative) / VISIBLE_ARC, 2.0) * 0.65
