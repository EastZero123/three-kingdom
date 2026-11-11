class_name UiStyle
extends RefCounted
## 화면 공용 색과 스타일. 색을 한곳에 모아 두면 나중에 테마를 바꾸기 쉽다.

const BACKGROUND: Color = Color("1b1d22")
const PANEL: Color = Color("262a31")
const PANEL_DARK: Color = Color("20232a")
const BORDER: Color = Color("3a3f48")
const TEXT_DIM: Color = Color("9aa0a8")
const GOLD: Color = Color("f0c050")
const HEAL: Color = Color("6fd08a")
const MERGE: Color = Color("6cc4e8")
const DANGER: Color = Color("e06060")
const CHEST: Color = Color("f0a050")

const TIER_COLORS: Dictionary[String, Color] = {
	"F": Color("8a8a8a"), "E": Color("5fa55a"), "D": Color("3fa7a0"), "C": Color("4a7fd4"),
	"B": Color("9a5fd0"), "A": Color("e08a2e"), "S": Color("e0463a"),
}


static func tier_color(tier: String) -> Color:
	return TIER_COLORS.get(tier, BORDER)


static func box(background: Color, border: Color = BORDER, border_width: int = 1, radius: int = 6) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


## 체력 비율에 따른 막대 색: 절반 넘으면 초록, 4분의 1 넘으면 노랑, 그 아래는 빨강.
static func hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Color("5cbf6a")
	if ratio > 0.25:
		return Color("e0b040")
	return DANGER


static func label(text: String, font_size: int = 18, color: Color = Color.WHITE) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result
