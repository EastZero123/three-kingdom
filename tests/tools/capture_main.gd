extends SceneTree
## 메인 씬을 띄워 화면을 PNG로 저장하고 종료하는 확인용 도구.
## 실행: godot --path . -s tests/tools/capture_main.gd -- <저장할 png 경로>

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const WAIT_FRAMES: int = 5


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("저장할 PNG 경로를 인자로 넘겨야 한다.")
		quit(1)
		return

	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	root.add_child(packed.instantiate())
	_capture(args[0])


func _capture(output_path: String) -> void:
	# 화면이 실제로 그려질 때까지 몇 프레임 기다린다.
	for i: int in WAIT_FRAMES:
		await process_frame
	var image: Image = root.get_texture().get_image()
	var result: Error = image.save_png(output_path)
	print("화면 저장: %s (결과 코드 %d)" % [output_path, result])
	quit(0 if result == OK else 1)
