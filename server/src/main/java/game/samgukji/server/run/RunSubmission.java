package game.samgukji.server.run;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.Table;
import java.time.Instant;

/** 제출된 원정 기록 한 건 (run_submissions 표의 한 줄). */
@Entity
@Table(name = "run_submissions")
public class RunSubmission {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "player_name", nullable = false, length = 20)
    private String playerName;

    @Column(nullable = false)
    private long seed;

    /** 행동 기록 (게임이 보낸 JSON 배열 그대로). */
    @Lob
    @Column(name = "actions_json", nullable = false)
    private String actionsJson;

    /** 같은 기록을 두 번 올리지 못하게 막는 지문 (시드 + 행동 기록의 SHA-256). */
    @Column(name = "submission_hash", nullable = false, unique = true, length = 64)
    private String submissionHash;

    @Column(name = "game_version", nullable = false, length = 20)
    private String gameVersion;

    /** 게임이 주장한 결과. */
    @Column(name = "claimed_years", nullable = false)
    private int claimedYears;

    @Column(name = "final_year", nullable = false)
    private int finalYear;

    @Column(name = "final_round", nullable = false)
    private int finalRound;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private RunStatus status = RunStatus.PENDING;

    /** 검증에서 다시 실행해 얻은 생존 연수 (검증 전에는 null). */
    @Column(name = "verified_years")
    private Integer verifiedYears;

    /** 거부된 이유 (검증 스크립트의 영문 코드). */
    @Column(name = "reject_reason", length = 40)
    private String rejectReason;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "verified_at")
    private Instant verifiedAt;

    protected RunSubmission() {
        // JPA용
    }

    public RunSubmission(String playerName, long seed, String actionsJson, String submissionHash, String gameVersion,
                         int claimedYears, int finalYear, int finalRound) {
        this.playerName = playerName;
        this.seed = seed;
        this.actionsJson = actionsJson;
        this.submissionHash = submissionHash;
        this.gameVersion = gameVersion;
        this.claimedYears = claimedYears;
        this.finalYear = finalYear;
        this.finalRound = finalRound;
    }

    public void markVerified(int years) {
        this.status = RunStatus.VERIFIED;
        this.verifiedYears = years;
        this.rejectReason = null;
        this.verifiedAt = Instant.now();
    }

    public void markRejected(String reason) {
        this.status = RunStatus.REJECTED;
        this.rejectReason = reason;
        this.verifiedAt = Instant.now();
    }

    public Long getId() { return id; }
    public String getPlayerName() { return playerName; }
    public long getSeed() { return seed; }
    public String getActionsJson() { return actionsJson; }
    public String getSubmissionHash() { return submissionHash; }
    public String getGameVersion() { return gameVersion; }
    public int getClaimedYears() { return claimedYears; }
    public int getFinalYear() { return finalYear; }
    public int getFinalRound() { return finalRound; }
    public RunStatus getStatus() { return status; }
    public Integer getVerifiedYears() { return verifiedYears; }
    public String getRejectReason() { return rejectReason; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getVerifiedAt() { return verifiedAt; }
}
