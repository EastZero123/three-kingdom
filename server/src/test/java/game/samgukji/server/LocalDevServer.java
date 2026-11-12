package game.samgukji.server;

import org.springframework.boot.SpringApplication;

/**
 * MySQL 없이 메모리 DB(H2)로 서버를 띄운다 (개발·확인용). 서버를 끄면 데이터는 사라진다.
 * IntelliJ에서 이 클래스를 실행하면 된다. 검증까지 하려면 환경 변수 GODOT_PATH, GAME_PROJECT_PATH를 넣는다.
 * 설정은 src/test/resources/application-test.yml을 쓴다.
 */
public final class LocalDevServer {

    private LocalDevServer() {
    }

    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(RankingServerApplication.class);
        app.setAdditionalProfiles("test");
        app.run(args);
    }
}
