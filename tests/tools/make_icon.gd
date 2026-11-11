extends SceneTree
## 임시 아이콘을 그려 res://ui/icon.png(256px)와 res://ui/icon.ico(16~256px)를 만든다.
## 디자인: 짙은 붉은 인장 바탕 + 금색 테두리 + 한자 "征"(원정). 그림이 생기면 이 두 파일만 바꾸면 된다.
## 실행 (화면이 필요해 --headless 없이): godot --path . -s tests/tools/make_icon.gd

const SIZE: int = 256
const ICO_SIZES: Array[int] = [16, 24, 32, 48, 64, 128, 256]
const GLYPH: String = "征"


func _initialize() -> void:
	_make()


func _make() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var seal: Panel = Panel.new()
	seal.position = Vector2(8, 8)
	seal.size = Vector2(SIZE - 16, SIZE - 16)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("8e1f1f")
	style.border_color = Color("e9c46a")
	style.set_border_width_all(10)
	style.set_corner_radius_all(36)
	seal.add_theme_stylebox_override("panel", style)
	viewport.add_child(seal)

	var label: Label = Label.new()
	label.text = GLYPH
	label.position = Vector2.ZERO
	label.size = Vector2(SIZE, SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", load("res://ui/fonts/NotoSansKR-Bold.ttf") as Font)
	label.add_theme_font_size_override("font_size", 170)
	label.add_theme_color_override("font_color", Color("f6e7c1"))
	viewport.add_child(label)

	for i: int in 4:
		await process_frame
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)

	var png_path: String = "res://ui/icon.png"
	var ok: bool = image.save_png(png_path) == OK
	ok = _save_ico(image, "res://ui/icon.ico") and ok
	print("아이콘 %s: %s, res://ui/icon.ico" % ["저장" if ok else "저장 실패", png_path])
	quit(0 if ok else 1)


## ICO 파일 형식: 머리말(6바이트) + 크기별 항목(16바이트씩) + 각 크기의 PNG 데이터.
## Windows Vista 이후로 ICO 안에 PNG를 그대로 넣을 수 있다.
func _save_ico(source: Image, path: String) -> bool:
	var pngs: Array[PackedByteArray] = []
	for icon_size: int in ICO_SIZES:
		var resized: Image = source.duplicate() as Image
		resized.resize(icon_size, icon_size, Image.INTERPOLATE_LANCZOS)
		pngs.append(resized.save_png_to_buffer())

	var header: PackedByteArray = PackedByteArray()
	header.resize(6 + 16 * ICO_SIZES.size())
	header.encode_u16(0, 0)  # 예약
	header.encode_u16(2, 1)  # 1 = 아이콘
	header.encode_u16(4, ICO_SIZES.size())
	var offset: int = header.size()
	for i: int in ICO_SIZES.size():
		var entry: int = 6 + 16 * i
		var icon_size: int = ICO_SIZES[i]
		header.encode_u8(entry, 0 if icon_size >= 256 else icon_size)      # 너비 (256은 0으로 적는다)
		header.encode_u8(entry + 1, 0 if icon_size >= 256 else icon_size)  # 높이
		header.encode_u8(entry + 2, 0)   # 팔레트 색 수
		header.encode_u8(entry + 3, 0)   # 예약
		header.encode_u16(entry + 4, 1)  # 색 평면
		header.encode_u16(entry + 6, 32) # 픽셀당 비트
		header.encode_u32(entry + 8, pngs[i].size())
		header.encode_u32(entry + 12, offset)
		offset += pngs[i].size()

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("파일을 쓸 수 없다: %s" % path)
		return false
	file.store_buffer(header)
	for png: PackedByteArray in pngs:
		file.store_buffer(png)
	return true
