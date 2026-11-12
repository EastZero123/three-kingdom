package game.samgukji.server.verify;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

/** Godot 출력 해석과 입력 만들기 (Godot 없이 도는 단위 테스트). */
class GodotRunVerifierTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final GodotRunVerifier verifier = new GodotRunVerifier(new VerifierProperties("godot", "project", 10), objectMapper);

    @Test
    void passedResult() throws Exception {
        VerificationResult result = verifier.parseOutput(
                "Godot Engine v4.7.2\n게임 데이터: 장수 66명\nVERIFY_RESULT {\"ok\": true, \"years\": 5, \"year\": 189, \"round\": 3, \"reason\": \"\"}\n");
        assertThat(result.ok()).isTrue();
        assertThat(result.years()).isEqualTo(5);
    }

    @Test
    void rejectedResultIsNotRetryable() throws Exception {
        VerificationResult result = verifier.parseOutput("VERIFY_RESULT {\"ok\": false, \"years\": 2, \"reason\": \"result_mismatch\"}");
        assertThat(result.ok()).isFalse();
        assertThat(result.retryable()).isFalse();
        assertThat(result.reason()).isEqualTo("result_mismatch");
    }

    @Test
    void missingResultLineIsServerProblem() throws Exception {
        VerificationResult result = verifier.parseOutput("SCRIPT ERROR: 무언가 잘못됨\n");
        assertThat(result.retryable()).isTrue();
        assertThat(result.reason()).isEqualTo("verifier_no_result");
    }

    @Test
    void serverSideReasonsAreRetryable() throws Exception {
        for (String reason : new String[] {"server_data_invalid", "no_input", "cannot_read_input", "bad_json"}) {
            VerificationResult result = verifier.parseOutput("VERIFY_RESULT {\"ok\":false,\"reason\":\"" + reason + "\"}");
            assertThat(result.retryable()).as(reason).isTrue();
        }
    }

    @Test
    void recordProblemsAreNotRetryable() throws Exception {
        for (String reason : new String[] {"result_mismatch", "replay_diverged", "run_not_finished", "game_version", "bad_action"}) {
            VerificationResult result = verifier.parseOutput("VERIFY_RESULT {\"ok\":false,\"reason\":\"" + reason + "\"}");
            assertThat(result.retryable()).as(reason).isFalse();
        }
    }

    @Test
    void notConfiguredIsServerProblem() {
        GodotRunVerifier unconfigured = new GodotRunVerifier(new VerifierProperties("", "", null), objectMapper);
        VerificationResult result = unconfigured.verify(new VerificationRequest(1, "[]", 0, 184, 1, "0.2.0"));
        assertThat(result.retryable()).isTrue();
        assertThat(result.reason()).isEqualTo("verifier_not_configured");
    }

    @Test
    void inputUsesScriptFieldNames() throws Exception {
        JsonNode input = objectMapper.readTree(verifier.buildInput(
                new VerificationRequest(12345, "[{\"type\":\"draft\",\"index\":0}]", 3, 187, 4, "0.2.0")));
        assertThat(input.get("seed").asLong()).isEqualTo(12345);
        assertThat(input.get("actions").get(0).get("type").asText()).isEqualTo("draft");
        assertThat(input.get("game_version").asText()).isEqualTo("0.2.0");
        assertThat(input.get("round").asInt()).isEqualTo(4);
    }
}
