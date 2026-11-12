package game.samgukji.server.verify;

/** 검증할 기록: 시드, 행동 기록(JSON 배열 문자열), 주장한 결과, 게임 버전. */
public record VerificationRequest(
        long seed,
        String actionsJson,
        int years,
        int year,
        int round,
        String gameVersion) {
}
