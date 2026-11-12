package game.samgukji.server;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.scheduling.annotation.EnableAsync;

/**
 * 온라인 랭킹 서버의 시작점.
 * <ul>
 *   <li>POST /runs — 끝난 원정 기록(시드 + 행동 기록 + 주장한 결과)을 받는다.</li>
 *   <li>GET /runs/{id} — 제출한 기록의 검증 상태를 본다.</li>
 *   <li>GET /leaderboard — 검증을 통과한 기록의 순위.</li>
 * </ul>
 * 검증은 Godot 헤드리스로 같은 기록을 다시 실행해 결과가 같은지 확인한다 (비동기).
 */
@SpringBootApplication
@EnableAsync
@ConfigurationPropertiesScan
public class RankingServerApplication {

    public static void main(String[] args) {
        SpringApplication.run(RankingServerApplication.class, args);
    }
}
