extends Control

@onready var nick_edit: LineEdit = $Center/VBox/NickEdit
@onready var ip_edit: LineEdit = $Center/VBox/IpEdit
@onready var status: Label = $Center/VBox/Status

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	nick_edit.text = Net.nickname
	ip_edit.text = "127.0.0.1"
	$Center/VBox/IpHint.text = "твой LAN-IP для братвы: " + Net.lan_ip()
	status.text = Net.parting_msg
	Net.parting_msg = ""
	$Center/VBox/HostBtn.pressed.connect(_on_host)
	$Center/VBox/JoinBtn.pressed.connect(_on_join)
	$Center/VBox/QuitBtn.pressed.connect(_on_quit)
	Net.join_failed.connect(_on_join_failed)

func _grab_nick() -> void:
	var n := nick_edit.text.strip_edges().substr(0, 24)
	Net.nickname = n if not n.is_empty() else "Бро"

func _on_host() -> void:
	_grab_nick()
	var err := Net.host()
	if err != OK:
		status.text = "не взлетело, код %d (порт занят?)" % err

func _on_join() -> void:
	_grab_nick()
	status.text = "стучимся в %s ..." % ip_edit.text
	var err := Net.join(ip_edit.text)
	if err != OK:
		status.text = "клиент не создался, код %d" % err

func _on_join_failed() -> void:
	status.text = "хост молчит... проверь IP и файрвол (UDP %d)" % Net.PORT

func _on_quit() -> void:
	get_tree().quit()