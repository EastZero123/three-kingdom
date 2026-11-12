-- 제출된 원정 기록. 검증을 통과한(VERIFIED) 기록만 순위에 보인다.
CREATE TABLE run_submissions (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    player_name     VARCHAR(20)  NOT NULL,
    seed            BIGINT       NOT NULL,
    actions_json    LONGTEXT     NOT NULL,
    submission_hash VARCHAR(64)  NOT NULL,
    game_version    VARCHAR(20)  NOT NULL,
    claimed_years   INT          NOT NULL,
    final_year      INT          NOT NULL,
    final_round     INT          NOT NULL,
    status          VARCHAR(10)  NOT NULL,
    verified_years  INT          NULL,
    reject_reason   VARCHAR(40)  NULL,
    created_at      DATETIME(6)  NOT NULL,
    verified_at     DATETIME(6)  NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_run_submissions_hash (submission_hash),
    KEY idx_run_submissions_rank (status, verified_years, final_year, final_round, created_at)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
