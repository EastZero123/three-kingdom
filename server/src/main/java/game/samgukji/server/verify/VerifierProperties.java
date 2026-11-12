package game.samgukji.server.verify;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 검증기 설정 (application.yml의 verifier.*).
 *
 * @param godotPath      Godot 실행 파일 경로. Windows에서는 *_console.exe를 쓴다 (출력을 읽어야 하므로).
 * @param projectPath    게임 프로젝트 폴더 (project.godot가 있는 곳). 서버는 이 폴더의 core/와 data/로 다시 실행한다.
 * @param timeoutSeconds 검증 한 건의 최대 시간
 */
@ConfigurationProperties(prefix = "verifier")
public record VerifierProperties(String godotPath, String projectPath, Integer timeoutSeconds) {

    public int timeoutOrDefault() {
        return timeoutSeconds == null || timeoutSeconds <= 0 ? 60 : timeoutSeconds;
    }

    public boolean isConfigured() {
        return godotPath != null && !godotPath.isBlank() && projectPath != null && !projectPath.isBlank();
    }
}
