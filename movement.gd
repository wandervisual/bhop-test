extends CharacterBody3D

const WALK_SPEED = 12.0
const MAX_AIR_SPEED = 45.0
const ACCEL_AIR = 0.25
const JUMP_VELOCITY = 5.5

const MOUSE_SENSITIVITY = 0.003
const TOUCH_SENSITIVITY = 0.005
const JOYSTICK_MAX_RANGE = 70.0

@onready var camera: Camera3D = $Camera3D

# Ноды интерфейса
var mobile_ui: CanvasLayer
var joystick_base: Panel
var joystick_stick: Panel
var speed_label: Label
var nickname_label: Label3D

# Переменные тача
var joystick_active = false
var joystick_center = Vector2(150.0, 480.0)
var joystick_vector = Vector2.ZERO
var touch_pointer_id = -1

@export var player_nickname: String = "Игрок":
	set(value):
		player_nickname = value
		if nickname_label:
			nickname_label.text = value

func _ready():
	# 1. Создаем ник над головой
	nickname_label = Label3D.new()
	nickname_label.text = player_nickname
	nickname_label.position = Vector3(0, 1.5, 0)
	nickname_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(nickname_label)
	
	# СКРЫТИЕ СВОЕГО НИКА:
	if is_multiplayer_authority():
		nickname_label.visible = false
	
	# 2. Генерируем текстуру круга кодом
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.5))
	gradient.set_color(1, Color(1, 1, 1, 0))
	
	var circle_tex = GradientTexture2D.new()
	circle_tex.gradient = gradient
	circle_tex.fill = GradientTexture2D.FILL_RADIAL
	circle_tex.fill_from = Vector2(0.5, 0.5)
	circle_tex.fill_to = Vector2(0.5, 0.0)
	circle_tex.width = 128
	circle_tex.height = 128

	# 3. Создаем контейнер интерфейса
	mobile_ui = CanvasLayer.new()
	add_child(mobile_ui)

	# Спидометр
	speed_label = Label.new()
	speed_label.text = "Скорость: 0.0"
	speed_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	speed_label.anchor_left = 1.0
	speed_label.anchor_right = 1.0
	
	var window_size = get_viewport().get_window().size
	speed_label.position = Vector2(float(window_size.x) - 220.0, 20.0)
	mobile_ui.add_child(speed_label)

	# Оставляем мышку видимой для главного меню при старте
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Если мы на ПК — просто прячем мобильные кнопки, но мышь пока НЕ захватываем!
	if not DisplayServer.is_touchscreen_available():
		mobile_ui.visible = false
		return
	
	# Код для мобилок
	mobile_ui.visible = true
	
	joystick_base = Panel.new()
	joystick_base.size = Vector2(150.0, 150.0)
	joystick_base.position = joystick_center - Vector2(75.0, 75.0)
	var style_base = StyleBoxTexture.new()
	style_base.texture = circle_tex
	joystick_base.add_theme_stylebox_override("panel", style_base)
	mobile_ui.add_child(joystick_base)
	
	joystick_stick = Panel.new()
	joystick_stick.size = Vector2(60.0, 60.0)
	joystick_stick.position = Vector2(45.0, 45.0)
	var style_stick = StyleBoxTexture.new()
	style_stick.texture = circle_tex
	joystick_stick.add_theme_stylebox_override("panel", style_stick)
	joystick_base.add_child(joystick_stick)
	
	var jump_btn = TouchScreenButton.new()
	jump_btn.texture_normal = circle_tex
	jump_btn.action = "ui_accept"
	jump_btn.position = Vector2(float(window_size.x) - 200.0, 420.0)
	mobile_ui.add_child(jump_btn)

func _input(event):
	if not is_multiplayer_authority(): return

	# Активация обзора мыши по клику на экран (когда зашел на сервер)
	if event is InputEventMouseButton and event.pressed and not DisplayServer.is_touchscreen_available():
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Обзор мышкой работает только если мышь захвачена
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
		
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x < float(get_viewport().get_window().size.x) / 2.0:
			if event.position.distance_to(joystick_center) < 120.0:
				joystick_active = true
				touch_pointer_id = event.index
				update_joystick(event.position)
		elif not event.pressed and event.index == touch_pointer_id:
			joystick_active = false
			touch_pointer_id = -1
			joystick_vector = Vector2.ZERO
			if joystick_stick:
				joystick_stick.position = Vector2(45.0, 45.0)

	if event is InputEventScreenDrag:
		if joystick_active and event.index == touch_pointer_id:
			update_joystick(event.position)
		else:
			if event.position.x > 250.0:
				rotate_y(-event.relative.x * TOUCH_SENSITIVITY)
				camera.rotate_x(-event.relative.y * TOUCH_SENSITIVITY)
				camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

	if Input.is_key_pressed(KEY_ESCAPE):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func update_joystick(touch_pos: Vector2):
	var offset = touch_pos - joystick_center
	if offset.length() > JOYSTICK_MAX_RANGE:
		offset = offset.normalized() * JOYSTICK_MAX_RANGE
	
	if joystick_stick:
		joystick_stick.position = (offset + Vector2(75.0, 75.0)) - Vector2(30.0, 30.0)
		
	joystick_vector = offset / JOYSTICK_MAX_RANGE

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority(): return

	if not is_on_floor():
		velocity += get_gravity() * delta

	# Проверяем зажатие кнопки прыжка
	var wishing_to_jump = Input.is_key_pressed(KEY_SPACE) or Input.is_action_pressed("ui_accept")

	if wishing_to_jump and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_W): input_dir.y -= 1
	if Input.is_key_pressed(KEY_S): input_dir.y += 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	
	if joystick_active:
		input_dir = joystick_vector
	else:
		input_dir = input_dir.normalized()

	var wish_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Обход запинки при авто-бхопе
	if is_on_floor() and not wishing_to_jump:
		if wish_dir:
			velocity.x = wish_dir.x * WALK_SPEED
			velocity.z = wish_dir.z * WALK_SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, WALK_SPEED * 0.2)
			velocity.z = move_toward(velocity.z, 0, WALK_SPEED * 0.2)
	else:
		# Физика плавного бхопа
		if wish_dir:
			var current_speed_in_wish_dir = velocity.dot(wish_dir)
			var add_speed = MAX_AIR_SPEED - current_speed_in_wish_dir
			
			if add_speed > 0:
				var accel_amount = ACCEL_AIR * WALK_SPEED * delta * 60.0
				if accel_amount > add_speed:
					accel_amount = add_speed
				velocity.x += wish_dir.x * accel_amount
				velocity.z += wish_dir.z * accel_amount
			
			var speed_3d = Vector3(velocity.x, 0, velocity.z)
			if speed_3d.length() > MAX_AIR_SPEED:
				speed_3d = speed_3d.normalized() * MAX_AIR_SPEED
				velocity.x = speed_3d.x
				velocity.z = speed_3d.z

	move_and_slide()

	if global_position.y < -20.0:
		global_position = Vector3(0, 10.0, 0)
		velocity = Vector3.ZERO

	# Обновление спидометра
	var horizontal_velocity := Vector3(velocity.x, 0, velocity.z)
	var current_speed := horizontal_velocity.length()
	if speed_label:
		speed_label.text = "Скорость: " + str(snapped(current_speed, 0.1))
