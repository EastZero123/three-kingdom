package game.samgukji.server.run;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 온라인 랭킹 API. */
@RestController
@Validated
public class RunController {

    private final RunService runService;

    public RunController(RunService runService) {
        this.runService = runService;
    }

    /**
     * 끝난 원정 기록을 제출한다. 검증은 따로 진행되므로 바로 202(접수)를 돌려준다.
     * 같은 기록을 다시 보내면 409와 함께 기존 기록의 상태를 돌려준다.
     */
    @PostMapping("/runs")
    public ResponseEntity<RunResponse> submit(@Valid @RequestBody SubmitRunRequest request) {
        RunService.SubmitResult result = runService.submit(request);
        HttpStatus status = result.duplicate() ? HttpStatus.CONFLICT : HttpStatus.ACCEPTED;
        return ResponseEntity.status(status).body(RunResponse.from(result.run()));
    }

    @GetMapping("/runs/{id}")
    public ResponseEntity<RunResponse> find(@PathVariable Long id) {
        return runService.find(id)
                .map(run -> ResponseEntity.ok(RunResponse.from(run)))
                .orElse(ResponseEntity.notFound().build());
    }

    /** 검증을 통과한 기록의 순위. limit은 1~100. */
    @GetMapping("/leaderboard")
    public List<LeaderboardEntry> leaderboard(@RequestParam(defaultValue = "20") @Min(1) @Max(100) int limit) {
        return runService.leaderboard(limit);
    }
}
