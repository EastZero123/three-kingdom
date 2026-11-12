package game.samgukji.server.run;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

/** 기록 제출과 순위 조회. */
@Service
public class RunService {

    private final RunSubmissionRepository repository;
    private final VerificationService verificationService;
    private final ObjectMapper objectMapper;

    public RunService(RunSubmissionRepository repository, VerificationService verificationService, ObjectMapper objectMapper) {
        this.repository = repository;
        this.verificationService = verificationService;
        this.objectMapper = objectMapper;
    }

    /** 제출 결과: 새로 저장했는지, 이미 같은 기록이 있었는지. */
    public record SubmitResult(RunSubmission run, boolean duplicate) {
    }

    /**
     * 기록을 저장하고 검증을 시작한다. 같은 시드·같은 행동 기록이 이미 있으면 새로 저장하지 않는다.
     * repository.save()가 끝나면 DB에 반영되므로, 그 뒤에 검증을 시작해야 검증 스레드가 기록을 찾을 수 있다.
     */
    public SubmitResult submit(SubmitRunRequest request) {
        String actionsJson = toJson(request.actions());
        String hash = sha256(request.seed() + ":" + actionsJson);
        Optional<RunSubmission> existing = repository.findBySubmissionHash(hash);
        if (existing.isPresent()) {
            return new SubmitResult(existing.get(), true);
        }
        RunSubmission saved = repository.save(new RunSubmission(
                request.playerName().strip(), request.seed(), actionsJson, hash, request.gameVersion(),
                request.years(), request.year(), request.round()));
        verificationService.verifyAsync(saved.getId());
        return new SubmitResult(saved, false);
    }

    public Optional<RunSubmission> find(Long id) {
        return repository.findById(id);
    }

    public List<LeaderboardEntry> leaderboard(int limit) {
        List<RunSubmission> runs = repository.findByStatusOrderByVerifiedYearsDescFinalYearDescFinalRoundDescCreatedAtAsc(
                RunStatus.VERIFIED, PageRequest.of(0, limit));
        List<LeaderboardEntry> result = new ArrayList<>();
        for (int i = 0; i < runs.size(); i++) {
            RunSubmission run = runs.get(i);
            result.add(new LeaderboardEntry(i + 1, run.getPlayerName(), run.getVerifiedYears(), run.getFinalYear(),
                    run.getFinalRound(), run.getSeed(), run.getGameVersion(), run.getVerifiedAt()));
        }
        return result;
    }

    private String toJson(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("행동 기록을 JSON으로 바꿀 수 없습니다", e);
        }
    }

    private static String sha256(String text) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
