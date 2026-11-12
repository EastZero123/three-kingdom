package game.samgukji.server.verify;

/**
 * 검증 결과.
 *
 * @param ok        다시 실행한 결과가 주장과 같으면 true
 * @param years     다시 실행해 얻은 생존 연수 (알 수 없으면 null)
 * @param reason    실패 이유 코드 (검증 스크립트의 reason, 또는 서버 쪽 문제)
 * @param retryable 서버 쪽 문제(설정 누락, 시간 초과 등)라서 나중에 다시 검증해야 하면 true.
 *                  기록 자체의 문제(조작, 버전 불일치)면 false.
 */
public record VerificationResult(boolean ok, Integer years, String reason, boolean retryable) {

    public static VerificationResult passed(int years) {
        return new VerificationResult(true, years, "", false);
    }

    public static VerificationResult rejected(String reason, Integer years) {
        return new VerificationResult(false, years, reason, false);
    }

    public static VerificationResult serverProblem(String reason) {
        return new VerificationResult(false, null, reason, true);
    }
}
