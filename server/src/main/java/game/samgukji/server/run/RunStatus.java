package game.samgukji.server.run;

/** 제출된 기록의 검증 상태. */
public enum RunStatus {
    /** 검증 대기 중 */
    PENDING,
    /** 다시 실행한 결과가 주장과 같아 순위에 오른다 */
    VERIFIED,
    /** 다시 실행할 수 없거나 결과가 달라 거부됐다 */
    REJECTED
}
