package game.samgukji.server.run;

import java.time.Instant;

/** 순위 한 줄 (GET /leaderboard 응답). */
public record LeaderboardEntry(
        int rank,
        String playerName,
        int years,
        int finalYear,
        int finalRound,
        long seed,
        String gameVersion,
        Instant verifiedAt) {
}
