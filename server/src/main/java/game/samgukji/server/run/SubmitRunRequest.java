package game.samgukji.server.run;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.Map;

/**
 * POST /runs 요청 본문. 게임의 로컬 기록(RunRecords)과 같은 내용이다.
 *
 * @param playerName  순위에 보일 이름
 * @param seed        런 시드
 * @param actions     행동 기록 (예: {"type": "expedition", "index": 0})
 * @param years       게임이 주장하는 생존 연수
 * @param year        패배한 연도
 * @param round       패배한 라운드
 * @param gameVersion 게임 버전 (project.godot의 application/config/version)
 */
public record SubmitRunRequest(
        @NotBlank @Size(max = 20) String playerName,
        @NotNull @PositiveOrZero Long seed,
        @NotEmpty @Size(max = 20000) List<Map<String, Object>> actions,
        @NotNull @Min(0) @Max(10000) Integer years,
        @NotNull @Min(0) Integer year,
        @NotNull @Min(1) @Max(100) Integer round,
        @NotBlank @Size(max = 20) String gameVersion) {
}
