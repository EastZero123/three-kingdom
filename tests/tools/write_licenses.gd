extends SceneTree
## 배포용 라이선스 고지 파일을 만든다. 엔진이 직접 알려 주는 정보를 쓰므로 엔진 버전이 바뀌어도 맞춰진다.
## 실행: godot --headless --path . -s tests/tools/write_licenses.gd -- <저장 폴더>
## 만드는 파일:
##   GODOT_LICENSE.txt       Godot 엔진 라이선스 (MIT)
##   THIRD_PARTY_NOTICES.txt 엔진에 포함된 서드파티 구성 요소의 저작권과 라이선스 전문
##   FONT_NOTO_SANS_KR_OFL.txt 한글 폰트 라이선스 (res://ui/fonts/OFL.txt 복사)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("저장 폴더를 인자로 넘겨야 한다.")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var info: Dictionary = Engine.get_version_info()
	var godot_text: String = "이 게임은 Godot Engine %s 로 만들어졌다.\n\n%s\n" % [info["string"], Engine.get_license_text()]
	var ok: bool = _write(out_dir.path_join("GODOT_LICENSE.txt"), godot_text)

	var lines: PackedStringArray = []
	lines.append("Godot Engine에 포함된 서드파티 구성 요소")
	lines.append("================================================")
	lines.append("")
	for component: Dictionary in Engine.get_copyright_info():
		lines.append("■ %s" % component["name"])
		for part: Dictionary in component["parts"]:
			for holder: String in part["copyright"]:
				lines.append("  Copyright %s" % holder)
			lines.append("  License: %s" % part["license"])
		lines.append("")
	lines.append("")
	lines.append("라이선스 전문")
	lines.append("================================================")
	var licenses: Dictionary = Engine.get_license_info()
	var names: Array = licenses.keys()
	names.sort()
	for license_name: Variant in names:
		lines.append("")
		lines.append("----- %s -----" % license_name)
		lines.append(String(licenses[license_name]))
	ok = _write(out_dir.path_join("THIRD_PARTY_NOTICES.txt"), "\n".join(lines)) and ok

	var font_license: String = FileAccess.get_file_as_string("res://ui/fonts/OFL.txt")
	if font_license.is_empty():
		push_error("res://ui/fonts/OFL.txt를 읽지 못했다.")
		ok = false
	else:
		ok = _write(out_dir.path_join("FONT_NOTO_SANS_KR_OFL.txt"),
			"한글 폰트: Noto Sans KR (SIL Open Font License 1.1)\n\n" + font_license) and ok

	print("라이선스 파일 %s: %s" % ["저장" if ok else "저장 실패", out_dir])
	quit(0 if ok else 1)


func _write(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("파일을 쓸 수 없다: %s" % path)
		return false
	file.store_string(text)
	return true
