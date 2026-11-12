package game.samgukji.server.verify;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Godot 헤드리스로 게임 로직을 다시 실행해 기록을 검증한다.
 * 실행 명령: godot --headless --path <프로젝트> -s verify/verify_run.gd -- <입력 JSON 파일>
 * 결과는 출력의 "VERIFY_RESULT {...}" 줄에서 읽는다.
 */
@Component
public class GodotRunVerifier implements RunVerifier {

    static final String RESULT_PREFIX = "VERIFY_RESULT ";
    /** 검증 스크립트의 실패 이유 중 기록이 아니라 서버 쪽 문제인 것. */
    static final java.util.Set<String> SERVER_SIDE_REASONS =
            java.util.Set.of("server_data_invalid", "no_input", "cannot_read_input", "bad_json");
    private static final Logger log = LoggerFactory.getLogger(GodotRunVerifier.class);

    private final VerifierProperties properties;
    private final ObjectMapper objectMapper;

    public GodotRunVerifier(VerifierProperties properties, ObjectMapper objectMapper) {
        this.properties = properties;
        this.objectMapper = objectMapper;
    }

    @Override
    public VerificationResult verify(VerificationRequest request) {
        if (!properties.isConfigured()) {
            return VerificationResult.serverProblem("verifier_not_configured");
        }
        Path input = null;
        try {
            input = Files.createTempFile("samgukji-run-", ".json");
            Files.writeString(input, buildInput(request), StandardCharsets.UTF_8);
            ProcessBuilder builder = new ProcessBuilder(List.of(
                    properties.godotPath(), "--headless", "--path", properties.projectPath(),
                    "-s", "verify/verify_run.gd", "--", input.toString()));
            builder.redirectErrorStream(true);
            Process process = builder.start();
            // 출력을 따로 읽어 두어야 출력이 많아도 프로세스가 멈추지 않는다.
            CompletableFuture<String> output = CompletableFuture.supplyAsync(() -> readAll(process));
            if (!process.waitFor(properties.timeoutOrDefault(), TimeUnit.SECONDS)) {
                process.destroyForcibly();
                return VerificationResult.serverProblem("verifier_timeout");
            }
            return parseOutput(output.get(5, TimeUnit.SECONDS));
        } catch (Exception e) {
            log.warn("검증 실행 실패", e);
            return VerificationResult.serverProblem("verifier_error");
        } finally {
            if (input != null) {
                try {
                    Files.deleteIfExists(input);
                } catch (IOException ignored) {
                    // 임시 파일 정리 실패는 무시한다
                }
            }
        }
    }

    /** 검증 스크립트가 읽는 입력 JSON을 만든다. */
    String buildInput(VerificationRequest request) throws IOException {
        ObjectNode root = objectMapper.createObjectNode();
        root.put("seed", request.seed());
        root.set("actions", objectMapper.readTree(request.actionsJson()));
        root.put("years", request.years());
        root.put("year", request.year());
        root.put("round", request.round());
        root.put("game_version", request.gameVersion());
        return objectMapper.writeValueAsString(root);
    }

    /** Godot 출력에서 결과 줄을 찾아 해석한다. 결과 줄이 없으면 서버 쪽 문제로 본다. */
    VerificationResult parseOutput(String output) throws IOException {
        String line = output.lines()
                .filter(l -> l.startsWith(RESULT_PREFIX))
                .reduce((first, second) -> second)
                .orElse(null);
        if (line == null) {
            log.warn("검증 결과 줄이 없습니다. 출력 끝부분: {}", tail(output));
            return VerificationResult.serverProblem("verifier_no_result");
        }
        JsonNode result = objectMapper.readTree(line.substring(RESULT_PREFIX.length()));
        Integer years = result.hasNonNull("years") ? result.get("years").asInt() : null;
        if (result.path("ok").asBoolean(false) && years != null) {
            return VerificationResult.passed(years);
        }
        String reason = result.path("reason").asText("unknown");
        // 서버 쪽 문제는 기록 탓이 아니므로 거부하지 않고 나중에 다시 검증한다.
        //   server_data_invalid: 서버의 게임 데이터가 잘못됨
        //   no_input, cannot_read_input, bad_json: 서버가 만든 입력 파일을 Godot가 읽지 못함 (권한·경로 문제)
        if (SERVER_SIDE_REASONS.contains(reason)) {
            log.warn("검증 스크립트가 서버 쪽 문제를 알렸습니다: {}", line);
            return VerificationResult.serverProblem(reason);
        }
        return VerificationResult.rejected(reason, years);
    }

    private static String readAll(Process process) {
        try {
            return new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            return "";
        }
    }

    private static String tail(String output) {
        return output.length() <= 500 ? output : output.substring(output.length() - 500);
    }
}
