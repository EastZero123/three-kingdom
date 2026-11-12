package game.samgukji.server.run;

import java.time.Instant;

/** 제출한 기록의 상태 (POST /runs, GET /runs/{id} 응답). */
public record RunResponse(
        Long id,
        String playerName,
        RunStatus status,
        int claimedYears,
        Integer verifiedYears,
        String rejectReason,
        Instant createdAt) {

    static RunResponse from(RunSubmission run) {
        return new RunResponse(run.getId(), run.getPlayerName(), run.getStatus(), run.getClaimedYears(),
                run.getVerifiedYears(), run.getRejectReason(), run.getCreatedAt());
    }
}
