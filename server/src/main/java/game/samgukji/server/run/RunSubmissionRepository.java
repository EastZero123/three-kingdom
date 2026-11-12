package game.samgukji.server.run;

import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

/** run_submissions 표 접근. 메서드 이름으로 쿼리가 만들어진다 (Spring Data JPA). */
public interface RunSubmissionRepository extends JpaRepository<RunSubmission, Long> {

    Optional<RunSubmission> findBySubmissionHash(String submissionHash);

    List<RunSubmission> findByStatus(RunStatus status);

    /** 순위: 생존 연수 → 더 멀리 간 연도·라운드 → 먼저 올린 기록 순. 게임의 로컬 기록 순위와 같은 기준. */
    List<RunSubmission> findByStatusOrderByVerifiedYearsDescFinalYearDescFinalRoundDescCreatedAtAsc(
            RunStatus status, Pageable pageable);
}
