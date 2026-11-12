package game.samgukji.server.run;

import game.samgukji.server.verify.RunVerifier;
import game.samgukji.server.verify.VerificationRequest;
import game.samgukji.server.verify.VerificationResult;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

/**
 * 제출된 기록을 검증하고 결과를 DB에 적는다.
 * 검증은 Godot를 실행해 1~2초씩 걸리므로 요청과 따로(비동기로) 처리한다.
 * 서버가 켜질 때는 아직 검증하지 못한(PENDING) 기록을 다시 검증한다.
 */
@Service
public class VerificationService {

    private static final Logger log = LoggerFactory.getLogger(VerificationService.class);

    private final RunSubmissionRepository repository;
    private final RunVerifier verifier;

    public VerificationService(RunSubmissionRepository repository, RunVerifier verifier) {
        this.repository = repository;
        this.verifier = verifier;
    }

    /** @Async: 이 메서드는 별도 스레드에서 돈다 (application.yml의 spring.task.execution 설정). */
    @Async
    public void verifyAsync(Long id) {
        verifyNow(id);
    }

    public void verifyNow(Long id) {
        RunSubmission run = repository.findById(id).orElse(null);
        if (run == null || run.getStatus() != RunStatus.PENDING) {
            return;
        }
        VerificationResult result = verifier.verify(new VerificationRequest(
                run.getSeed(), run.getActionsJson(), run.getClaimedYears(), run.getFinalYear(),
                run.getFinalRound(), run.getGameVersion()));
        if (result.ok()) {
            run.markVerified(result.years());
        } else if (result.retryable()) {
            // 서버 쪽 문제: 기록은 그대로 대기 상태로 두고, 다음에 서버가 켜질 때 다시 검증한다.
            log.warn("기록 {} 검증을 미룹니다: {}", id, result.reason());
            return;
        } else {
            run.markRejected(result.reason());
        }
        repository.save(run);
        log.info("기록 {} 검증: {} ({})", id, run.getStatus(), result.reason());
    }

    @EventListener(ApplicationReadyEvent.class)
    public void verifyPendingOnStartup() {
        for (RunSubmission run : repository.findByStatus(RunStatus.PENDING)) {
            verifyAsync(run.getId());
        }
    }
}
