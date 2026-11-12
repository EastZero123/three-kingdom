package game.samgukji.server.verify;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.InputStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

/**
 * 진짜 Godot로 표본 기록을 검증한다. 환경 변수 GODOT_PATH와 GAME_PROJECT_PATH가 있을 때만 돈다.
 * 표본 기록(sample_finished_run.json)은 게임 쪽 tests/tools/make_sample_run.gd로 만든다.
 */
@EnabledIfEnvironmentVariable(named = "GODOT_PATH", matches = ".+")
class GodotRunVerifierIntegrationTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final GodotRunVerifier verifier = new GodotRunVerifier(
            new VerifierProperties(System.getenv("GODOT_PATH"), System.getenv("GAME_PROJECT_PATH"), 120), objectMapper);

    @Test
    void honestSamplePasses() throws Exception {
        JsonNode sample = sample();
        VerificationResult result = verifier.verify(request(sample, sample.get("years").asInt()));
        assertThat(result.ok()).as("검증 결과: %s", result).isTrue();
        assertThat(result.years()).isEqualTo(sample.get("years").asInt());
    }

    @Test
    void inflatedSampleIsRejected() throws Exception {
        JsonNode sample = sample();
        VerificationResult result = verifier.verify(request(sample, sample.get("years").asInt() + 10));
        assertThat(result.ok()).isFalse();
        assertThat(result.retryable()).isFalse();
        assertThat(result.reason()).isEqualTo("result_mismatch");
    }

    private JsonNode sample() throws Exception {
        try (InputStream in = getClass().getResourceAsStream("/sample_finished_run.json")) {
            return objectMapper.readTree(in);
        }
    }

    private VerificationRequest request(JsonNode sample, int years) throws Exception {
        return new VerificationRequest(sample.get("seed").asLong(), objectMapper.writeValueAsString(sample.get("actions")),
                years, sample.get("year").asInt(), sample.get("round").asInt(), sample.get("gameVersion").asText());
    }
}
