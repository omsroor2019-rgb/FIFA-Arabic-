extends Node3D

# Football Arena — self-contained 3D football prototype.
# All geometry is generated from Godot primitives; no unlicensed external assets.

const FIELD_W: float = 38.0
const FIELD_L: float = 60.0
const MATCH_SECONDS: float = 180.0 # 3 real minutes = 90 displayed match minutes.
const PLAYER_SPEED: float = 6.8
const SPRINT_SPEED: float = 9.2
const BALL_RADIUS: float = 0.32

var home_team: Array[CharacterBody3D] = []
var away_team: Array[CharacterBody3D] = []
var active_player: CharacterBody3D
var ball: RigidBody3D
var camera_3d: Camera3D
var ui_layer: CanvasLayer
var ui_root: Control
var menu_overlay: ColorRect
var score_label: Label
var clock_label: Label
var info_label: Label
var joy_ring: Panel
var joy_center: Vector2 = Vector2.ZERO
var joy_vector: Vector2 = Vector2.ZERO
var joy_finger: int = -1
var sprint_left: float = 0.0
var match_state: String = "menu"
var match_elapsed: float = 0.0
var home_score: int = 0
var away_score: int = 0
var home_positions: Array[Vector3] = []
var away_positions: Array[Vector3] = []
var coins: int = 2000
var experience: int = 0
var roster: Array = []
var market_offers: Array = []
var last_pack_text: String = "لم تفتح بكجاً بعد"
var toast_timer: float = 0.0

const FIRST_NAMES: Array[String] = ["آدم", "سامي", "ريان", "مازن", "ياسر", "عمر", "نادر", "فارس", "زياد", "سيف", "مالك", "بدر", "رامي", "نديم", "حازم", "ليث", "جود", "كريم"]
const LAST_NAMES: Array[String] = ["العمري", "السالمي", "الحربي", "الحمادي", "النعيمي", "الراشد", "التميمي", "الزيدي", "المنصوري", "العبيدي", "الهاشمي", "القحطاني"]
const POSITIONS: Array[String] = ["حارس", "دفاع", "وسط", "هجوم"]


func _ready() -> void:
    randomize()
    _load_profile()
    _create_environment()
    _create_stadium()
    _create_pitch()
    _create_goals()
    _create_teams()
    _create_ball()
    _create_camera()
    _create_ui()
    _show_menu("home")


func _process(delta: float) -> void:
    if match_state == "match":
        match_elapsed += delta
        if sprint_left > 0.0:
            sprint_left = maxf(0.0, sprint_left - delta)
        if toast_timer > 0.0:
            toast_timer -= delta
            if toast_timer <= 0.0 and info_label != null:
                info_label.text = ""
        _update_clock_ui()
        _update_camera(delta)
        if match_elapsed >= MATCH_SECONDS:
            _finish_match()
    elif match_state == "finished":
        _update_camera(delta)


func _physics_process(delta: float) -> void:
    if match_state != "match":
        return
    _update_human_player(delta)
    _update_ai_team(home_team, true, delta)
    _update_ai_team(away_team, false, delta)
    _update_ball_and_rules(delta)


func _input(event: InputEvent) -> void:
    if match_state != "match":
        return
    var viewport_size: Vector2 = get_viewport().get_visible_rect().size
    if event is InputEventScreenTouch:
        if event.pressed:
            if event.position.x < viewport_size.x * 0.43 and event.position.y > viewport_size.y * 0.52 and joy_finger == -1:
                joy_finger = event.index
                joy_center = Vector2(138.0, viewport_size.y - 128.0)
                _set_joystick(event.position)
                get_viewport().set_input_as_handled()
        elif event.index == joy_finger:
            joy_finger = -1
            joy_vector = Vector2.ZERO
            get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag and event.index == joy_finger:
        _set_joystick(event.position)
        get_viewport().set_input_as_handled()


func _set_joystick(position_on_screen: Vector2) -> void:
    joy_vector = ((position_on_screen - joy_center) / 72.0).limit_length(1.0)


func _create_environment() -> void:
    var world := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.012, 0.035, 0.028)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.72, 0.82, 0.76)
    environment.ambient_light_energy = 0.78
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world.environment = environment
    add_child(world)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
    sun.light_energy = 1.25
    sun.shadow_enabled = true
    add_child(sun)


func _material(color: Color, roughness_value: float = 0.82, metallic_value: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness_value
    material.metallic = metallic_value
    return material


func _add_box(parent: Node3D, size: Vector3, position: Vector3, material: Material, node_name: String = "Mesh") -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = node_name
    var mesh := BoxMesh.new()
    mesh.size = size
    instance.mesh = mesh
    instance.material_override = material
    instance.position = position
    parent.add_child(instance)
    return instance


func _add_line(a: Vector3, b: Vector3, material: Material, thickness: float = 0.085) -> void:
    var line := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(thickness, 0.035, a.distance_to(b))
    line.mesh = mesh
    line.material_override = material
    line.position = (a + b) * 0.5
    line.look_at(b, Vector3.UP)
    add_child(line)


func _create_stadium() -> void:
    var concrete := _material(Color(0.075, 0.09, 0.105), 0.94)
    var tier_a := _material(Color(0.12, 0.19, 0.22))
    var tier_b := _material(Color(0.18, 0.23, 0.24))
    var seat_a := _material(Color(0.07, 0.35, 0.29))
    var seat_b := _material(Color(0.75, 0.52, 0.12))
    _add_box(self, Vector3(78, 0.8, 82), Vector3(0, -0.65, 0), concrete, "StadiumBase")

    for side in [-1.0, 1.0]:
        var x: float = side * 24.5
        _add_box(self, Vector3(10.0, 6.2, 70.0), Vector3(x, 2.7, 0), tier_a, "LongStand")
        for row in range(5):
            var row_y: float = 0.5 + float(row) * 1.08
            var row_x: float = side * (20.2 + float(row) * 1.0)
            for section in range(10):
                var z: float = -30.0 + float(section) * 6.6
                var seat_mat: Material = seat_a if (section + row) % 4 != 0 else seat_b
                _add_box(self, Vector3(0.32, 0.35, 5.0), Vector3(row_x, row_y, z), seat_mat, "StandSeat")

    for end_side in [-1.0, 1.0]:
        _add_box(self, Vector3(52.0, 6.0, 8.0), Vector3(0, 2.6, end_side * 35.5), tier_b, "EndStand")
        for row in range(4):
            for section in range(12):
                var x_pos: float = -24.0 + float(section) * 4.35
                var y_pos: float = 0.5 + float(row) * 1.15
                var z_pos: float = end_side * (31.8 + float(row) * 1.0)
                var seat_mat: Material = seat_b if section % 5 == 0 else seat_a
                _add_box(self, Vector3(3.6, 0.32, 0.3), Vector3(x_pos, y_pos, z_pos), seat_mat, "EndSeat")

    var light_pole_mat := _material(Color(0.16, 0.18, 0.19), 0.35, 0.55)
    var lamp_mat := _material(Color(0.95, 0.91, 0.72), 0.25, 0.1)
    for x_side in [-1.0, 1.0]:
        for z_side in [-1.0, 1.0]:
            var pole := MeshInstance3D.new()
            var pole_mesh := CylinderMesh.new()
            pole_mesh.top_radius = 0.13
            pole_mesh.bottom_radius = 0.2
            pole_mesh.height = 17.0
            pole.mesh = pole_mesh
            pole.material_override = light_pole_mat
            pole.position = Vector3(x_side * 30.5, 8.5, z_side * 31.0)
            add_child(pole)
            _add_box(self, Vector3(2.0, 0.35, 0.8), Vector3(x_side * 30.5, 17.0, z_side * 31.0), lamp_mat, "Floodlight")


func _create_pitch() -> void:
    var ground := StaticBody3D.new()
    ground.name = "PitchCollision"
    var ground_mesh := MeshInstance3D.new()
    var floor_box := BoxMesh.new()
    floor_box.size = Vector3(FIELD_W, 0.5, FIELD_L)
    ground_mesh.mesh = floor_box
    ground_mesh.material_override = _material(Color(0.035, 0.19, 0.075))
    ground_mesh.position.y = -0.25
    ground.add_child(ground_mesh)
    var collision := CollisionShape3D.new()
    var collision_box := BoxShape3D.new()
    collision_box.size = Vector3(FIELD_W, 0.5, FIELD_L)
    collision.shape = collision_box
    collision.position.y = -0.25
    ground.add_child(collision)
    add_child(ground)

    for stripe_index in range(10):
        var stripe_color: Color = Color(0.075, 0.34, 0.15) if stripe_index % 2 == 0 else Color(0.055, 0.29, 0.125)
        var stripe_material := _material(stripe_color)
        _add_box(self, Vector3(FIELD_W, 0.025, FIELD_L / 10.0), Vector3(0, 0.015, -FIELD_L / 2.0 + (float(stripe_index) + 0.5) * FIELD_L / 10.0), stripe_material, "GrassStripe")

    var white := _material(Color(0.93, 0.96, 0.9), 0.7)
    var left_x: float = -FIELD_W / 2.0 + 0.5
    var right_x: float = FIELD_W / 2.0 - 0.5
    var top_z: float = -FIELD_L / 2.0 + 0.5
    var bottom_z: float = FIELD_L / 2.0 - 0.5
    _add_line(Vector3(left_x, 0.055, top_z), Vector3(right_x, 0.055, top_z), white)
    _add_line(Vector3(left_x, 0.055, bottom_z), Vector3(right_x, 0.055, bottom_z), white)
    _add_line(Vector3(left_x, 0.055, top_z), Vector3(left_x, 0.055, bottom_z), white)
    _add_line(Vector3(right_x, 0.055, top_z), Vector3(right_x, 0.055, bottom_z), white)
    _add_line(Vector3(left_x, 0.055, 0), Vector3(right_x, 0.055, 0), white)
    _draw_circle(4.8, white)
    _draw_rectangle(-8.5, 8.5, -30.0, -20.0, white)
    _draw_rectangle(-8.5, 8.5, 20.0, 30.0, white)
    _draw_rectangle(-4.0, 4.0, -30.0, -25.5, white)
    _draw_rectangle(-4.0, 4.0, 25.5, 30.0, white)
    _add_box(self, Vector3(0.22, 0.045, 0.22), Vector3(0, 0.06, -23.0), white, "PenaltySpot")
    _add_box(self, Vector3(0.22, 0.045, 0.22), Vector3(0, 0.06, 23.0), white, "PenaltySpot")


func _draw_rectangle(x1: float, x2: float, z1: float, z2: float, material: Material) -> void:
    _add_line(Vector3(x1, 0.06, z1), Vector3(x2, 0.06, z1), material)
    _add_line(Vector3(x1, 0.06, z2), Vector3(x2, 0.06, z2), material)
    _add_line(Vector3(x1, 0.06, z1), Vector3(x1, 0.06, z2), material)
    _add_line(Vector3(x2, 0.06, z1), Vector3(x2, 0.06, z2), material)


func _draw_circle(radius: float, material: Material) -> void:
    var segments: int = 64
    for segment in range(segments):
        var a1: float = TAU * float(segment) / float(segments)
        var a2: float = TAU * float(segment + 1) / float(segments)
        _add_line(Vector3(cos(a1) * radius, 0.06, sin(a1) * radius), Vector3(cos(a2) * radius, 0.06, sin(a2) * radius), material, 0.065)


func _create_goals() -> void:
    var post_material := _material(Color(0.96, 0.97, 0.93), 0.28, 0.15)
    var net_material := _material(Color(0.72, 0.78, 0.75, 0.7), 0.8)
    for sign in [-1.0, 1.0]:
        var front_z: float = sign * 29.7
        var back_z: float = sign * 32.2
        _add_box(self, Vector3(0.16, 2.45, 0.16), Vector3(-3.7, 1.22, front_z), post_material, "GoalPost")
        _add_box(self, Vector3(0.16, 2.45, 0.16), Vector3(3.7, 1.22, front_z), post_material, "GoalPost")
        _add_box(self, Vector3(7.55, 0.16, 0.16), Vector3(0, 2.42, front_z), post_material, "GoalCrossbar")
        _add_box(self, Vector3(0.12, 2.35, 2.5), Vector3(-3.7, 1.2, (front_z + back_z) * 0.5), net_material, "GoalNetSide")
        _add_box(self, Vector3(0.12, 2.35, 2.5), Vector3(3.7, 1.2, (front_z + back_z) * 0.5), net_material, "GoalNetSide")
        _add_box(self, Vector3(7.4, 2.35, 0.1), Vector3(0, 1.2, back_z), net_material, "GoalNetBack")
        for net_x in range(9):
            var x: float = -3.6 + float(net_x) * 0.9
            _add_box(self, Vector3(0.035, 2.25, 0.035), Vector3(x, 1.15, back_z - sign * 0.08), net_material, "NetThread")
        for net_y in range(1, 5):
            _add_box(self, Vector3(7.35, 0.035, 0.035), Vector3(0, float(net_y) * 0.45, back_z - sign * 0.08), net_material, "NetThread")


func _create_teams() -> void:
    var formation_home: Array[Vector3] = [
        Vector3(0, 0, 26), Vector3(-13, 0, 17), Vector3(-4.5, 0, 18), Vector3(4.5, 0, 18), Vector3(13, 0, 17),
        Vector3(-12, 0, 5), Vector3(-4, 0, 4), Vector3(4, 0, 4), Vector3(12, 0, 5), Vector3(-6.5, 0, -12), Vector3(6.5, 0, -12)
    ]
    var formation_away: Array[Vector3] = []
    for position in formation_home:
        formation_away.append(Vector3(position.x, 0, -position.z))
    var blue := Color(0.035, 0.23, 0.88)
    var red := Color(0.82, 0.055, 0.075)
    var used_roster_indices: Array[int] = []
    for index in range(11):
        var selected_data: Dictionary = _select_lineup_player(index, used_roster_indices)
        var home_rating: int = int(selected_data.get("rating", 70))
        var away_rating: int = randi_range(66, 79)
        var home_player := _create_player(formation_home[index], blue, Color(0.035, 0.06, 0.16), index + 1, true, home_rating, str(selected_data.get("name", "Player")))
        var away_player := _create_player(formation_away[index], red, Color(0.12, 0.035, 0.045), index + 1, false, away_rating, "Red Team " + str(index + 1))
        home_team.append(home_player)
        away_team.append(away_player)
        home_positions.append(formation_home[index])
        away_positions.append(formation_away[index])
    active_player = home_team[9]
    _highlight_active_player()


func _select_lineup_player(slot_index: int, used_indices: Array[int]) -> Dictionary:
    var required_position: String = "حارس" if slot_index == 0 else ("دفاع" if slot_index <= 4 else ("وسط" if slot_index <= 8 else "هجوم"))
    var selected_index: int = -1
    var best_rating: int = -1
    for index in range(roster.size()):
        if used_indices.has(index):
            continue
        var candidate: Dictionary = roster[index]
        if str(candidate.get("position", "")) == required_position and int(candidate.get("rating", 0)) > best_rating:
            selected_index = index
            best_rating = int(candidate.get("rating", 0))
    if selected_index == -1:
        for index in range(roster.size()):
            if not used_indices.has(index) and int(roster[index].get("rating", 0)) > best_rating:
                selected_index = index
                best_rating = int(roster[index].get("rating", 0))
    if selected_index == -1:
        return {"name": "Player", "rating": 70, "position": required_position}
    used_indices.append(selected_index)
    return roster[selected_index]


func _apply_best_roster_to_team() -> void:
    var used_indices: Array[int] = []
    for index in range(home_team.size()):
        var selected_data: Dictionary = _select_lineup_player(index, used_indices)
        home_team[index].set_meta("rating", int(selected_data.get("rating", 70)))
        home_team[index].set_meta("roster_name", str(selected_data.get("name", "Player")))


func _create_player(position_on_pitch: Vector3, shirt_color: Color, shorts_color: Color, shirt_number: int, is_home: bool, rating: int = 70, display_name: String = "Player") -> CharacterBody3D:
    var player := CharacterBody3D.new()
    player.name = ("Home_" if is_home else "Away_") + str(shirt_number)
    player.position = position_on_pitch
    player.set_meta("home", is_home)
    player.set_meta("number", shirt_number)
    player.set_meta("rating", rating)
    player.set_meta("roster_name", display_name)
    player.set_meta("home_position", position_on_pitch)
    player.set_meta("kick_cooldown", randf_range(0.1, 1.0))

    var collision := CollisionShape3D.new()
    var capsule_shape := CapsuleShape3D.new()
    capsule_shape.radius = 0.34
    capsule_shape.height = 1.86
    collision.shape = capsule_shape
    collision.position.y = 0.93
    player.add_child(collision)

    var skin_tone := _material(Color(0.61 + randf() * 0.22, 0.39 + randf() * 0.18, 0.25 + randf() * 0.13))
    var hair_material := _material(Color(0.055, 0.035, 0.025), 0.96)
    var jersey := _material(shirt_color, 0.68)
    var shorts := _material(shorts_color)
    var sock_material := _material(Color(0.9, 0.91, 0.88))
    var boot_material := _material(Color(0.035, 0.04, 0.045), 0.36, 0.1)

    var torso := MeshInstance3D.new()
    var torso_mesh := CapsuleMesh.new()
    torso_mesh.radius = 0.32
    torso_mesh.height = 1.03
    torso.mesh = torso_mesh
    torso.material_override = jersey
    torso.position = Vector3(0, 1.26, 0)
    player.add_child(torso)

    var chest_panel := MeshInstance3D.new()
    var chest_mesh := BoxMesh.new()
    chest_mesh.size = Vector3(0.32, 0.55, 0.035)
    chest_panel.mesh = chest_mesh
    chest_panel.material_override = _material(shirt_color.lightened(0.26))
    chest_panel.position = Vector3(0, 1.3, -0.298)
    player.add_child(chest_panel)

    var neck := MeshInstance3D.new()
    var neck_mesh := CylinderMesh.new()
    neck_mesh.top_radius = 0.105
    neck_mesh.bottom_radius = 0.12
    neck_mesh.height = 0.17
    neck.mesh = neck_mesh
    neck.material_override = skin_tone
    neck.position.y = 1.78
    player.add_child(neck)

    var head := MeshInstance3D.new()
    var head_mesh := SphereMesh.new()
    head_mesh.radius = 0.22
    head_mesh.height = 0.44
    head.mesh = head_mesh
    head.material_override = skin_tone
    head.position = Vector3(0, 1.98, -0.01)
    player.add_child(head)

    var hair := MeshInstance3D.new()
    var hair_mesh := SphereMesh.new()
    hair_mesh.radius = 0.225
    hair_mesh.height = 0.19
    hair.mesh = hair_mesh
    hair.material_override = hair_material
    hair.position = Vector3(0, 2.12, 0.015)
    player.add_child(hair)

    for eye_side in [-1.0, 1.0]:
        var eye := MeshInstance3D.new()
        var eye_mesh := SphereMesh.new()
        eye_mesh.radius = 0.025
        eye_mesh.height = 0.05
        eye.mesh = eye_mesh
        eye.material_override = _material(Color(0.025, 0.025, 0.02), 0.4)
        eye.position = Vector3(eye_side * 0.075, 2.0, -0.205)
        player.add_child(eye)
    var mouth := MeshInstance3D.new()
    var mouth_mesh := BoxMesh.new()
    mouth_mesh.size = Vector3(0.075, 0.012, 0.012)
    mouth.mesh = mouth_mesh
    mouth.material_override = _material(Color(0.17, 0.075, 0.045))
    mouth.position = Vector3(0, 1.91, -0.213)
    player.add_child(mouth)
    for stripe_side in [-1.0, 1.0]:
        var jersey_stripe := MeshInstance3D.new()
        var stripe_mesh := BoxMesh.new()
        stripe_mesh.size = Vector3(0.055, 0.43, 0.04)
        jersey_stripe.mesh = stripe_mesh
        jersey_stripe.material_override = _material(shirt_color.lightened(0.3))
        jersey_stripe.position = Vector3(stripe_side * 0.235, 1.37, -0.13)
        player.add_child(jersey_stripe)

    var shorts_mesh_instance := MeshInstance3D.new()
    var shorts_mesh := CylinderMesh.new()
    shorts_mesh.top_radius = 0.27
    shorts_mesh.bottom_radius = 0.29
    shorts_mesh.height = 0.43
    shorts_mesh_instance.mesh = shorts_mesh
    shorts_mesh_instance.material_override = shorts
    shorts_mesh_instance.position.y = 0.75
    player.add_child(shorts_mesh_instance)

    var left_leg := Node3D.new()
    left_leg.position = Vector3(-0.16, 0.66, 0)
    player.add_child(left_leg)
    var right_leg := Node3D.new()
    right_leg.position = Vector3(0.16, 0.66, 0)
    player.add_child(right_leg)
    _add_limb_capsule(left_leg, 0.125, 0.73, Vector3(0, -0.27, 0), sock_material)
    _add_limb_capsule(right_leg, 0.125, 0.73, Vector3(0, -0.27, 0), sock_material)
    _add_box(left_leg, Vector3(0.26, 0.13, 0.38), Vector3(0, -0.64, -0.075), boot_material, "Boot")
    _add_box(right_leg, Vector3(0.26, 0.13, 0.38), Vector3(0, -0.64, -0.075), boot_material, "Boot")

    var left_arm := Node3D.new()
    left_arm.position = Vector3(-0.36, 1.5, 0)
    player.add_child(left_arm)
    var right_arm := Node3D.new()
    right_arm.position = Vector3(0.36, 1.5, 0)
    player.add_child(right_arm)
    _add_limb_capsule(left_arm, 0.105, 0.59, Vector3(0, -0.25, 0), jersey)
    _add_limb_capsule(right_arm, 0.105, 0.59, Vector3(0, -0.25, 0), jersey)
    _add_limb_capsule(left_arm, 0.082, 0.34, Vector3(0, -0.57, 0), skin_tone)
    _add_limb_capsule(right_arm, 0.082, 0.34, Vector3(0, -0.57, 0), skin_tone)

    player.set_meta("left_leg", left_leg)
    player.set_meta("right_leg", right_leg)
    player.set_meta("left_arm", left_arm)
    player.set_meta("right_arm", right_arm)
    player.set_meta("anim_phase", randf() * TAU)
    add_child(player)
    return player


func _add_limb_capsule(parent: Node3D, radius: float, height: float, local_position: Vector3, material: Material) -> void:
    var limb := MeshInstance3D.new()
    var mesh := CapsuleMesh.new()
    mesh.radius = radius
    mesh.height = height
    limb.mesh = mesh
    limb.material_override = material
    limb.position = local_position
    parent.add_child(limb)


func _create_ball() -> void:
    ball = RigidBody3D.new()
    ball.name = "MatchBall"
    ball.position = Vector3(0, BALL_RADIUS + 0.04, 0)
    ball.mass = 0.43
    ball.linear_damp = 0.38
    ball.angular_damp = 0.25
    ball.continuous_cd = true
    ball.contact_monitor = true
    ball.max_contacts_reported = 6

    var ball_mesh_node := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = BALL_RADIUS
    sphere.height = BALL_RADIUS * 2.0
    ball_mesh_node.mesh = sphere
    ball_mesh_node.material_override = _material(Color(0.95, 0.96, 0.91), 0.48)
    ball.add_child(ball_mesh_node)
    var patch_material := _material(Color(0.055, 0.065, 0.07), 0.65)
    for patch_position in [Vector3(0.0, 0.0, -0.295), Vector3(0.24, 0.11, 0.12), Vector3(-0.24, -0.12, 0.1), Vector3(0.0, 0.28, 0.08), Vector3(0.0, -0.26, -0.09)]:
        var patch := MeshInstance3D.new()
        var patch_mesh := SphereMesh.new()
        patch_mesh.radius = 0.065
        patch_mesh.height = 0.13
        patch.mesh = patch_mesh
        patch.material_override = patch_material
        patch.position = patch_position
        ball.add_child(patch)

    var collision := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = BALL_RADIUS
    collision.shape = shape
    ball.add_child(collision)
    add_child(ball)


func _create_camera() -> void:
    camera_3d = Camera3D.new()
    camera_3d.name = "BroadcastCamera"
    camera_3d.fov = 56.0
    camera_3d.position = Vector3(0, 43, 39)
    camera_3d.current = true
    add_child(camera_3d)
    camera_3d.look_at(Vector3.ZERO, Vector3.UP)


func _update_camera(delta: float) -> void:
    if camera_3d == null or ball == null:
        return
    var focus_x: float = clampf(ball.global_position.x * 0.36, -9.0, 9.0)
    var focus_z: float = clampf(ball.global_position.z * 0.43, -13.0, 13.0)
    var focus := Vector3(focus_x, 0.0, focus_z)
    var desired := focus + Vector3(0, 45.0, 40.0)
    camera_3d.global_position = camera_3d.global_position.lerp(desired, clampf(delta * 1.8, 0.0, 1.0))
    camera_3d.look_at(focus, Vector3.UP)


func _update_human_player(delta: float) -> void:
    if active_player == null:
        return
    var movement := joy_vector
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        movement.y -= 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        movement.y += 1.0
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        movement.x -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        movement.x += 1.0
    movement = movement.limit_length(1.0)
    var base_speed: float = SPRINT_SPEED if sprint_left > 0.0 else PLAYER_SPEED
    var rating_factor: float = clampf(float(active_player.get_meta("rating", 70)) / 75.0, 0.88, 1.14)
    var speed: float = base_speed * rating_factor
    var direction := Vector3(movement.x, 0.0, movement.y)
    active_player.velocity = direction * speed
    active_player.move_and_slide()
    if direction.length() > 0.08:
        active_player.look_at(active_player.global_position + direction.normalized(), Vector3.UP)
    _animate_player(active_player, delta, direction.length())
    active_player.global_position.x = clampf(active_player.global_position.x, -FIELD_W * 0.5 + 1.0, FIELD_W * 0.5 - 1.0)
    active_player.global_position.z = clampf(active_player.global_position.z, -FIELD_L * 0.5 + 1.0, FIELD_L * 0.5 - 1.0)


func _update_ai_team(team: Array[CharacterBody3D], is_home: bool, delta: float) -> void:
    var nearest: Array[CharacterBody3D] = []
    var nearest_distances: Array[float] = []
    for player in team:
        var distance: float = _flat_distance(player.global_position, ball.global_position)
        var insertion_index: int = nearest.size()
        for index in range(nearest_distances.size()):
            if distance < nearest_distances[index]:
                insertion_index = index
                break
        nearest.insert(insertion_index, player)
        nearest_distances.insert(insertion_index, distance)
    for player in team:
        if is_home and player == active_player:
            continue
        var base_position: Vector3 = player.get_meta("home_position")
        var distance_to_ball: float = _flat_distance(player.global_position, ball.global_position)
        var target: Vector3 = base_position
        if player == nearest[0] or (nearest.size() > 1 and player == nearest[1]) or (nearest.size() > 2 and player == nearest[2]):
            var attack_offset: float = 1.8 if is_home else -1.8
            target = Vector3(ball.global_position.x * 0.94, 0, ball.global_position.z + attack_offset)
        else:
            target.x = base_position.x + clampf(ball.global_position.x * 0.12, -2.8, 2.8)
            target.z = base_position.z + clampf(ball.global_position.z * (0.07 if is_home else -0.07), -2.5, 2.5)
        if int(player.get_meta("number", 0)) == 1:
            var keeper_z: float = 26.0 if is_home else -26.0
            target = Vector3(clampf(ball.global_position.x * 0.48, -3.0, 3.0), 0, keeper_z)
        target.x = clampf(target.x, -FIELD_W * 0.5 + 1.2, FIELD_W * 0.5 - 1.2)
        target.z = clampf(target.z, -FIELD_L * 0.5 + 1.2, FIELD_L * 0.5 - 1.2)
        var speed: float = 4.7 if distance_to_ball > 3.0 else 3.6
        speed *= clampf(float(player.get_meta("rating", 70)) / 75.0, 0.88, 1.12)
        _steer_player(player, target, speed, delta)
        var cooldown: float = float(player.get_meta("kick_cooldown", 0.0))
        cooldown = maxf(0.0, cooldown - delta)
        if cooldown <= 0.0 and _flat_distance(player.global_position, ball.global_position) < 1.35:
            var kick_direction := Vector3(0.0, 0.08, -1.0 if is_home else 1.0)
            kick_direction.x = clampf((randf() - 0.5) * 0.55, -0.25, 0.25)
            ball.apply_central_impulse(kick_direction.normalized() * randf_range(5.0, 8.0))
            cooldown = randf_range(1.0, 2.2)
        player.set_meta("kick_cooldown", cooldown)
        _animate_player(player, delta, player.velocity.length() / PLAYER_SPEED)


func _steer_player(player: CharacterBody3D, target: Vector3, speed: float, delta: float) -> void:
    var offset := target - player.global_position
    offset.y = 0.0
    var distance: float = offset.length()
    var direction := Vector3.ZERO
    if distance > 0.55:
        direction = offset.normalized()
    player.velocity = direction * speed
    player.move_and_slide()
    if direction.length() > 0.08:
        player.look_at(player.global_position + direction, Vector3.UP)
    player.global_position.x = clampf(player.global_position.x, -FIELD_W * 0.5 + 1.0, FIELD_W * 0.5 - 1.0)
    player.global_position.z = clampf(player.global_position.z, -FIELD_L * 0.5 + 1.0, FIELD_L * 0.5 - 1.0)


func _animate_player(player: CharacterBody3D, delta: float, movement_ratio: float) -> void:
    var phase: float = float(player.get_meta("anim_phase", 0.0)) + delta * (7.5 + movement_ratio * 8.0)
    player.set_meta("anim_phase", phase)
    var amount: float = clampf(movement_ratio, 0.0, 1.0)
    var left_leg: Node3D = player.get_meta("left_leg") as Node3D
    var right_leg: Node3D = player.get_meta("right_leg") as Node3D
    var left_arm: Node3D = player.get_meta("left_arm") as Node3D
    var right_arm: Node3D = player.get_meta("right_arm") as Node3D
    left_leg.rotation.x = sin(phase) * 0.62 * amount
    right_leg.rotation.x = sin(phase + PI) * 0.62 * amount
    left_arm.rotation.x = sin(phase + PI) * 0.42 * amount
    right_arm.rotation.x = sin(phase) * 0.42 * amount


func _flat_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x - b.x, a.z - b.z).length()


func _update_ball_and_rules(_delta: float) -> void:
    if absf(ball.global_position.x) > FIELD_W * 0.5 + 1.5:
        _reset_ball()
    if ball.global_position.z < -FIELD_L * 0.5 - 1.0:
        if absf(ball.global_position.x) < 3.85 and ball.global_position.y < 2.75:
            home_score += 1
            _show_toast("هدف لفريقك!")
        else:
            _show_toast("الكرة خارج الملعب")
        _reset_ball()
    elif ball.global_position.z > FIELD_L * 0.5 + 1.0:
        if absf(ball.global_position.x) < 3.85 and ball.global_position.y < 2.75:
            away_score += 1
            _show_toast("هدف للفريق المنافس")
        else:
            _show_toast("الكرة خارج الملعب")
        _reset_ball()
    if ball.global_position.y < -2.0:
        _reset_ball()


func _reset_ball() -> void:
    ball.global_position = Vector3(0, BALL_RADIUS + 0.05, 0)
    ball.linear_velocity = Vector3.ZERO
    ball.angular_velocity = Vector3.ZERO
    ball.sleeping = false


func _shoot_ball() -> void:
    if active_player == null or _flat_distance(active_player.global_position, ball.global_position) > 2.7:
        _show_toast("اقترب من الكرة أولاً")
        return
    var direction := Vector3(0, 0.12, -1)
    if active_player.velocity.length() > 0.8:
        direction = active_player.velocity.normalized() + Vector3(0, 0.1, 0)
    else:
        direction.x = clampf(-ball.global_position.x * 0.035, -0.28, 0.28)
    var shooter_factor: float = clampf(float(active_player.get_meta("rating", 70)) / 75.0, 0.85, 1.18)
    ball.apply_central_impulse(direction.normalized() * 15.5 * shooter_factor)


func _pass_ball() -> void:
    if active_player == null or _flat_distance(active_player.global_position, ball.global_position) > 2.7:
        _show_toast("اقترب من الكرة أولاً")
        return
    var teammate: CharacterBody3D = null
    var best_distance: float = INF
    for player in home_team:
        if player == active_player:
            continue
        var distance: float = _flat_distance(player.global_position, ball.global_position)
        if distance < best_distance:
            best_distance = distance
            teammate = player
    if teammate == null:
        return
    var direction: Vector3 = teammate.global_position - ball.global_position
    direction.y = 0.12
    var passer_factor: float = clampf(float(active_player.get_meta("rating", 70)) / 75.0, 0.85, 1.18)
    ball.apply_central_impulse(direction.normalized() * 9.2 * passer_factor)


func _switch_player() -> void:
    var closest: CharacterBody3D = home_team[0]
    var best_distance: float = INF
    for player in home_team:
        var distance: float = _flat_distance(player.global_position, ball.global_position)
        if distance < best_distance:
            best_distance = distance
            closest = player
    active_player = closest
    _highlight_active_player()


func _highlight_active_player() -> void:
    for player in home_team:
        # Active player is marked by a floating emerald ring, created lazily below.
        var marker: MeshInstance3D = player.get_node_or_null("ActiveMarker") as MeshInstance3D
        if player == active_player:
            if marker == null:
                marker = MeshInstance3D.new()
                marker.name = "ActiveMarker"
                var ring := TorusMesh.new()
                ring.inner_radius = 0.48
                ring.outer_radius = 0.62
                ring.rings = 32
                ring.ring_segments = 8
                marker.mesh = ring
                marker.material_override = _material(Color(0.16, 0.95, 0.55), 0.3, 0.15)
                marker.position = Vector3(0, 0.12, 0)
                player.add_child(marker)
            marker.visible = true
        elif marker != null:
            marker.visible = false


func _update_clock_ui() -> void:
    if score_label != null:
        score_label.text = "%d  -  %d" % [home_score, away_score]
    if clock_label != null:
        var shown_seconds: int = int((match_elapsed / MATCH_SECONDS) * 5400.0)
        clock_label.text = "%02d:%02d" % [shown_seconds / 60, shown_seconds % 60]


func _finish_match() -> void:
    if match_state != "match":
        return
    match_state = "finished"
    var reward: int = 1200 if home_score > away_score else (650 if home_score == away_score else 350)
    coins += reward
    experience += 120 if home_score > away_score else 50
    _save_profile()
    _show_menu("result", {"reward": reward})


func _show_toast(message: String) -> void:
    if info_label == null:
        return
    info_label.text = message
    toast_timer = 2.2


func _start_match() -> void:
    match_state = "match"
    match_elapsed = 0.0
    home_score = 0
    away_score = 0
    joy_vector = Vector2.ZERO
    joy_finger = -1
    sprint_left = 0.0
    for index in range(home_team.size()):
        home_team[index].global_position = home_positions[index]
        home_team[index].velocity = Vector3.ZERO
        away_team[index].global_position = away_positions[index]
        away_team[index].velocity = Vector3.ZERO
    active_player = home_team[9]
    _highlight_active_player()
    _reset_ball()
    _show_menu("")
    _set_game_hud_visible(true)
    _update_clock_ui()
    _show_toast("بدأت المباراة — تحكم باللاعب الأزرق")


func _pause_match() -> void:
    if match_state == "match":
        match_state = "paused"
        _show_menu("pause")
        _set_game_hud_visible(false)


func _resume_match() -> void:
    match_state = "match"
    _show_menu("")
    _set_game_hud_visible(true)


func _back_to_title() -> void:
    match_state = "menu"
    _save_profile()
    _show_menu("home")
    _set_game_hud_visible(false)


func _create_ui() -> void:
    ui_layer = CanvasLayer.new()
    add_child(ui_layer)
    ui_root = Control.new()
    ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_layer.add_child(ui_root)

    score_label = Label.new()
    score_label.position = Vector2(520, 16)
    score_label.size = Vector2(240, 56)
    score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    score_label.add_theme_font_size_override("font_size", 36)
    score_label.add_theme_color_override("font_color", Color.WHITE)
    score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    score_label.add_theme_constant_override("shadow_offset_x", 2)
    score_label.add_theme_constant_override("shadow_offset_y", 2)
    ui_root.add_child(score_label)

    clock_label = Label.new()
    clock_label.position = Vector2(555, 70)
    clock_label.size = Vector2(170, 35)
    clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    clock_label.add_theme_font_size_override("font_size", 22)
    clock_label.add_theme_color_override("font_color", Color(0.94, 0.85, 0.52))
    ui_root.add_child(clock_label)

    info_label = Label.new()
    info_label.position = Vector2(330, 630)
    info_label.size = Vector2(620, 48)
    info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    info_label.add_theme_font_size_override("font_size", 22)
    info_label.add_theme_color_override("font_color", Color.WHITE)
    ui_root.add_child(info_label)

    _create_touch_controls()
    _set_game_hud_visible(false)


func _create_touch_controls() -> void:
    var viewport_size: Vector2 = get_viewport().get_visible_rect().size
    joy_center = Vector2(138, viewport_size.y - 128)
    joy_ring = Panel.new()
    joy_ring.position = joy_center - Vector2(58, 58)
    joy_ring.size = Vector2(116, 116)
    var ring_style := StyleBoxFlat.new()
    ring_style.bg_color = Color(0.02, 0.07, 0.09, 0.42)
    ring_style.border_color = Color(0.85, 0.94, 0.9, 0.72)
    ring_style.set_border_width_all(2)
    ring_style.set_corner_radius_all(58)
    joy_ring.add_theme_stylebox_override("panel", ring_style)
    ui_root.add_child(joy_ring)

    var button_size := Vector2(128, 92)
    var shoot_button := _make_game_button("تسديد", Vector2(viewport_size.x - 155, viewport_size.y - 170), button_size, Color(0.68, 0.12, 0.10))
    shoot_button.pressed.connect(_shoot_ball)
    var pass_button := _make_game_button("تمرير", Vector2(viewport_size.x - 292, viewport_size.y - 112), Vector2(112, 70), Color(0.08, 0.36, 0.28))
    pass_button.pressed.connect(_pass_ball)
    var switch_button := _make_game_button("تبديل", Vector2(viewport_size.x - 292, viewport_size.y - 204), Vector2(112, 70), Color(0.09, 0.24, 0.52))
    switch_button.pressed.connect(_switch_player)
    var sprint_button := _make_game_button("انطلاق", Vector2(viewport_size.x - 155, viewport_size.y - 282), Vector2(128, 70), Color(0.48, 0.32, 0.07))
    sprint_button.pressed.connect(func(): sprint_left = 2.5)
    var pause_button := _make_game_button("Ⅱ", Vector2(viewport_size.x - 78, 22), Vector2(58, 54), Color(0.08, 0.11, 0.13, 0.82))
    pause_button.pressed.connect(_pause_match)


func _make_game_button(caption: String, position_on_screen: Vector2, button_size: Vector2, color: Color) -> Button:
    var button := Button.new()
    button.text = caption
    button.position = position_on_screen
    button.size = button_size
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 22)
    button.add_theme_color_override("font_color", Color.WHITE)
    var normal := StyleBoxFlat.new()
    normal.bg_color = color
    normal.set_corner_radius_all(18)
    normal.border_color = color.lightened(0.24)
    normal.set_border_width_all(1)
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = color.darkened(0.22)
    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", normal)
    button.add_theme_stylebox_override("pressed", pressed)
    ui_root.add_child(button)
    return button


func _set_game_hud_visible(visible_value: bool) -> void:
    if score_label == null:
        return
    score_label.visible = visible_value
    clock_label.visible = visible_value
    info_label.visible = visible_value
    joy_ring.visible = visible_value
    for child in ui_root.get_children():
        if child is Button:
            child.visible = visible_value


func _show_menu(page: String, extra: Dictionary = {}) -> void:
    if menu_overlay != null and is_instance_valid(menu_overlay):
        menu_overlay.queue_free()
        menu_overlay = null
    if page.is_empty():
        return

    var viewport_size: Vector2 = get_viewport().get_visible_rect().size
    menu_overlay = ColorRect.new()
    menu_overlay.color = Color(0.008, 0.018, 0.025, 0.82)
    menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    ui_root.add_child(menu_overlay)

    var panel := PanelContainer.new()
    panel.position = Vector2((viewport_size.x - 620.0) * 0.5, maxf(28.0, (viewport_size.y - 600.0) * 0.5))
    panel.size = Vector2(620, minf(630.0, viewport_size.y - 56.0))
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color(0.025, 0.06, 0.07, 0.97)
    panel_style.border_color = Color(0.13, 0.62, 0.43)
    panel_style.set_border_width_all(2)
    panel_style.set_corner_radius_all(24)
    panel.add_theme_stylebox_override("panel", panel_style)
    menu_overlay.add_child(panel)

    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 12)
    content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    content.offset_left = 28
    content.offset_top = 24
    content.offset_right = -28
    content.offset_bottom = -24
    panel.add_child(content)

    var title := Label.new()
    title.text = "FOOTBALL ARENA"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 34)
    title.add_theme_color_override("font_color", Color(0.35, 0.95, 0.66))
    content.add_child(title)

    var subtitle := Label.new()
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_font_size_override("font_size", 17)
    subtitle.add_theme_color_override("font_color", Color(0.84, 0.9, 0.88))
    content.add_child(subtitle)

    if page == "home":
        subtitle.text = "كرة قدم ثلاثية الأبعاد • أوفلاين • طور بناء الفريق"
        var profile := Label.new()
        profile.text = "الرصيد: %d عملة     |     الخبرة: %d XP     |     اللاعبون: %d" % [coins, experience, roster.size()]
        profile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        profile.add_theme_font_size_override("font_size", 19)
        profile.add_theme_color_override("font_color", Color(0.96, 0.82, 0.43))
        content.add_child(profile)
        _add_menu_button(content, "مباراة سريعة", _start_match, Color(0.08, 0.48, 0.31))
        _add_menu_button(content, "فريقي واللاعبون", func(): _show_menu("squad"), Color(0.09, 0.26, 0.42))
        _add_menu_button(content, "البكجات", func(): _show_menu("packs"), Color(0.32, 0.22, 0.52))
        _add_menu_button(content, "سوق الانتقالات", func(): _show_menu("market"), Color(0.47, 0.29, 0.08))
        var note := Label.new()
        note.text = "الفوز يمنح 1200 عملة • التعادل 650 • الخسارة 350"
        note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        note.add_theme_font_size_override("font_size", 15)
        note.add_theme_color_override("font_color", Color(0.7, 0.79, 0.76))
        content.add_child(note)

    elif page == "squad":
        subtitle.text = "قائمة فريقك — لاعبين خياليين بتقييمات قابلة للتطوير"
        var listing := Label.new()
        listing.text = _roster_summary()
        listing.add_theme_font_size_override("font_size", 15)
        listing.add_theme_color_override("font_color", Color(0.93, 0.95, 0.91))
        listing.size_flags_vertical = Control.SIZE_EXPAND_FILL
        content.add_child(listing)
        _add_menu_button(content, "تطوير أضعف لاعب", _upgrade_weakest_player, Color(0.15, 0.39, 0.31))
        _add_menu_button(content, "بيع أضعف لاعب", _sell_weakest_player, Color(0.42, 0.18, 0.15))
        _add_menu_button(content, "فتح البكجات", func(): _show_menu("packs"), Color(0.32, 0.22, 0.52))
        _add_menu_button(content, "رجوع", func(): _show_menu("home"), Color(0.12, 0.2, 0.22))

    elif page == "packs":
        subtitle.text = "افتح بكجاً عشوائياً وأضف لاعباً إلى تشكيلتك"
        var balance := Label.new()
        balance.text = "رصيدك: %d عملة" % coins
        balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        balance.add_theme_font_size_override("font_size", 21)
        balance.add_theme_color_override("font_color", Color(0.98, 0.82, 0.42))
        content.add_child(balance)
        var pack_description := Label.new()
        pack_description.text = "العادي: 300 عملة — تقييم متوقع 63 إلى 82\nالنادر: 900 عملة — تقييم متوقع 76 إلى 94\n\nآخر بطاقة: " + last_pack_text
        pack_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        pack_description.add_theme_font_size_override("font_size", 17)
        pack_description.add_theme_color_override("font_color", Color(0.87, 0.91, 0.87))
        content.add_child(pack_description)
        _add_menu_button(content, "فتح بكج عادي — 300", func(): _open_pack(false), Color(0.14, 0.36, 0.31))
        _add_menu_button(content, "فتح بكج نادر — 900", func(): _open_pack(true), Color(0.34, 0.22, 0.52))
        _add_menu_button(content, "رجوع", func(): _show_menu("home"), Color(0.12, 0.2, 0.22))

    elif page == "market":
        subtitle.text = "اشترِ لاعباً من السوق باستخدام العملات المكتسبة"
        var balance_market := Label.new()
        balance_market.text = "رصيدك: %d عملة" % coins
        balance_market.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        balance_market.add_theme_font_size_override("font_size", 20)
        balance_market.add_theme_color_override("font_color", Color(0.98, 0.82, 0.42))
        content.add_child(balance_market)
        if market_offers.is_empty():
            _refresh_market()
        for index in range(market_offers.size()):
            var offer: Dictionary = market_offers[index]
            var price: int = int(offer["price"])
            var offer_label := "%s  |  %s  |  تقييم %d  |  %d عملة" % [offer["name"], offer["position"], int(offer["rating"]), price]
            var buy_action: Callable = Callable(self, "_buy_market_player").bind(index)
            _add_menu_button(content, offer_label, buy_action, Color(0.18, 0.25, 0.35))
        _add_menu_button(content, "تحديث العروض", _regenerate_market, Color(0.47, 0.29, 0.08))
        _add_menu_button(content, "رجوع", func(): _show_menu("home"), Color(0.12, 0.2, 0.22))

    elif page == "pause":
        subtitle.text = "المباراة متوقفة مؤقتاً"
        _add_menu_button(content, "متابعة المباراة", _resume_match, Color(0.08, 0.48, 0.31))
        _add_menu_button(content, "الخروج للقائمة", _back_to_title, Color(0.34, 0.19, 0.17))

    elif page == "result":
        subtitle.text = "انتهت المباراة: %d - %d" % [home_score, away_score]
        var reward_label := Label.new()
        reward_label.text = "حصلت على %d عملة\nرصيدك الآن: %d" % [int(extra.get("reward", 0)), coins]
        reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        reward_label.add_theme_font_size_override("font_size", 25)
        reward_label.add_theme_color_override("font_color", Color(0.98, 0.83, 0.44))
        content.add_child(reward_label)
        _add_menu_button(content, "إعادة المباراة", _start_match, Color(0.08, 0.48, 0.31))
        _add_menu_button(content, "الفريق والبكجات", func(): _show_menu("home"), Color(0.09, 0.26, 0.42))


func _add_menu_button(parent: VBoxContainer, caption: String, action: Callable, color: Color) -> void:
    var button := Button.new()
    button.text = caption
    button.custom_minimum_size = Vector2(0, 54)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 19)
    button.add_theme_color_override("font_color", Color.WHITE)
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.set_corner_radius_all(14)
    style.border_color = color.lightened(0.2)
    style.set_border_width_all(1)
    var pressed_style := style.duplicate() as StyleBoxFlat
    pressed_style.bg_color = color.darkened(0.22)
    button.add_theme_stylebox_override("normal", style)
    button.add_theme_stylebox_override("hover", style)
    button.add_theme_stylebox_override("pressed", pressed_style)
    button.pressed.connect(action)
    parent.add_child(button)


func _roster_summary() -> String:
    var lines: Array[String] = []
    var shown: int = mini(roster.size(), 10)
    for index in range(shown):
        var player: Dictionary = roster[index]
        lines.append("%02d. %s | %s | %d | %s" % [index + 1, player["name"], player["position"], int(player["rating"]), player["rarity"]])
    lines.append("\nالتشكيلة الأساسية تختار أفضل اللاعبين حسب مراكزهم.")
    lines.append("آخر تحديث: " + last_pack_text)
    return "\n".join(lines)


func _weakest_player_index() -> int:
    if roster.is_empty():
        return -1
    var weakest: int = 0
    for index in range(1, roster.size()):
        if int(roster[index].get("rating", 0)) < int(roster[weakest].get("rating", 0)):
            weakest = index
    return weakest


func _upgrade_weakest_player() -> void:
    var weakest_index: int = _weakest_player_index()
    if weakest_index < 0:
        return
    var player: Dictionary = roster[weakest_index]
    var current_rating: int = int(player.get("rating", 60))
    if current_rating >= 95:
        last_pack_text = "هذا اللاعب وصل إلى الحد الأعلى"
        _show_menu("squad")
        return
    var cost: int = 450 + current_rating * 5
    if coins < cost:
        last_pack_text = "تحتاج %d عملة لتطوير اللاعب" % cost
        _show_menu("squad")
        return
    coins -= cost
    player["rating"] = mini(95, current_rating + 2)
    for skill in ["speed", "shoot", "pass", "defense"]:
        player[skill] = mini(99, int(player.get(skill, current_rating)) + 2)
    player["rarity"] = _rarity_name(int(player["rating"]))
    roster[weakest_index] = player
    last_pack_text = "تم تطوير %s بنجاح" % player["name"]
    _apply_best_roster_to_team()
    _save_profile()
    _show_menu("squad")


func _sell_weakest_player() -> void:
    if roster.size() <= 11:
        last_pack_text = "لا يمكن بيع المزيد؛ احتفظ بـ 11 لاعباً على الأقل"
        _show_menu("squad")
        return
    var weakest_index: int = _weakest_player_index()
    if weakest_index < 0:
        return
    var sold_player: Dictionary = roster[weakest_index]
    var price: int = maxi(150, int(sold_player.get("rating", 60)) * 10)
    coins += price
    roster.remove_at(weakest_index)
    last_pack_text = "تم بيع %s مقابل %d عملة" % [sold_player.get("name", "اللاعب"), price]
    _apply_best_roster_to_team()
    _save_profile()
    _show_menu("squad")


func _open_pack(is_rare: bool) -> void:
    var cost: int = 900 if is_rare else 300
    if coins < cost:
        last_pack_text = "رصيد غير كافٍ"
        _show_menu("packs")
        return
    coins -= cost
    var new_player: Dictionary = _generate_player(is_rare)
    roster.append(new_player)
    _apply_best_roster_to_team()
    last_pack_text = "%s — %s — %d (%s)" % [new_player["name"], new_player["position"], int(new_player["rating"]), new_player["rarity"]]
    _save_profile()
    _show_menu("packs")


func _generate_player(is_rare: bool) -> Dictionary:
    var rating: int
    if is_rare:
        var roll: float = randf()
        rating = randi_range(76, 84) if roll < 0.72 else (randi_range(85, 90) if roll < 0.95 else randi_range(91, 94))
    else:
        var roll_common: float = randf()
        rating = randi_range(63, 72) if roll_common < 0.72 else randi_range(73, 82)
    var position_index: int = randi_range(0, POSITIONS.size() - 1)
    var player_name: String = FIRST_NAMES[randi_range(0, FIRST_NAMES.size() - 1)] + " " + LAST_NAMES[randi_range(0, LAST_NAMES.size() - 1)]
    return {
        "name": player_name,
        "position": POSITIONS[position_index],
        "rating": rating,
        "rarity": _rarity_name(rating),
        "speed": clampi(rating + randi_range(-8, 8), 45, 99),
        "shoot": clampi(rating + randi_range(-10, 10), 40, 99),
        "pass": clampi(rating + randi_range(-9, 9), 40, 99),
        "defense": clampi(rating + randi_range(-12, 9), 35, 99)
    }


func _rarity_name(rating: int) -> String:
    if rating >= 91:
        return "أسطوري"
    if rating >= 85:
        return "نادر جداً"
    if rating >= 76:
        return "نادر"
    return "عادي"


func _refresh_market() -> void:
    market_offers.clear()
    for index in range(3):
        var offer := _generate_player(index == 2)
        var price: int = int(offer["rating"]) * (22 if offer["rarity"] == "عادي" else 31)
        offer["price"] = price
        market_offers.append(offer)


func _regenerate_market() -> void:
    _refresh_market()
    _show_menu("market")


func _buy_market_player(index: int) -> void:
    if index < 0 or index >= market_offers.size():
        return
    var offer: Dictionary = market_offers[index]
    var price: int = int(offer["price"])
    if coins < price:
        _show_menu("market")
        return
    coins -= price
    var purchased: Dictionary = offer.duplicate(true)
    purchased.erase("price")
    roster.append(purchased)
    _apply_best_roster_to_team()
    market_offers.remove_at(index)
    _save_profile()
    _show_menu("market")


func _load_profile() -> void:
    var config := ConfigFile.new()
    var error = config.load("user://profile.cfg")
    if error == OK:
        coins = int(config.get_value("profile", "coins", 2000))
        experience = int(config.get_value("profile", "experience", 0))
        var saved_roster: Variant = config.get_value("profile", "roster", [])
        if saved_roster is Array:
            roster = saved_roster
    if roster.is_empty():
        roster.clear()
        for index in range(18):
            var initial_player := _generate_player(false)
            if index == 0:
                initial_player["position"] = "حارس"
            elif index < 7:
                initial_player["position"] = "دفاع" if index < 5 else "وسط"
            else:
                initial_player["position"] = "وسط" if index < 12 else "هجوم"
            roster.append(initial_player)
        _save_profile()
    _refresh_market()


func _save_profile() -> void:
    var config := ConfigFile.new()
    config.set_value("profile", "coins", coins)
    config.set_value("profile", "experience", experience)
    config.set_value("profile", "roster", roster)
    config.save("user://profile.cfg")
