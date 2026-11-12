package game.samgukji.server.run;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doReturn;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import game.samgukji.server.verify.RunVerifier;
import game.samgukji.server.verify.VerificationResult;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

/** API 흐름 테스트: 제출 → (가짜) 검증 → 순위. 검증기는 가짜로 바꿔 Godot 없이 돌린다. */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class RunApiTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private RunSubmissionRepository repository;

    /** 진짜 검증기 대신 끼우는 가짜. 테스트마다 돌려줄 결과를 정한다. */
    @MockitoBean
    private RunVerifier verifier;

    @BeforeEach
    void clear() {
        repository.deleteAll();
        // 기본: 주장한 생존 연수를 그대로 통과시킨다. (doAnswer/doReturn 형식은 결과를 테스트 중간에 바꿔도 안전하다.)
        doAnswer(invocation -> VerificationResult.passed(
                ((game.samgukji.server.verify.VerificationRequest) invocation.getArgument(0)).years()))
                .when(verifier).verify(any());
    }

    @Test
    void submitThenVerifiedThenOnLeaderboard() throws Exception {
        MvcResult result = mvc.perform(post("/runs").contentType(MediaType.APPLICATION_JSON).content(body("조운", 7, 3)))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.status").value("PENDING"))
                .andReturn();
        long id = objectMapper.readTree(result.getResponse().getContentAsString()).get("id").asLong();

        assertThat(waitForStatus(id)).isEqualTo("VERIFIED");
        mvc.perform(get("/leaderboard"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].rank").value(1))
                .andExpect(jsonPath("$[0].playerName").value("조운"))
                .andExpect(jsonPath("$[0].years").value(7));
    }

    @Test
    void rejectedRunIsNotOnLeaderboard() throws Exception {
        doReturn(VerificationResult.rejected("result_mismatch", 1)).when(verifier).verify(any());
        long id = submit("조작", 99, 1);
        assertThat(waitForStatus(id)).isEqualTo("REJECTED");
        mvc.perform(get("/runs/" + id)).andExpect(jsonPath("$.rejectReason").value("result_mismatch"));
        mvc.perform(get("/leaderboard")).andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void serverProblemKeepsRunPending() throws Exception {
        doReturn(VerificationResult.serverProblem("verifier_not_configured")).when(verifier).verify(any());
        long id = submit("대기", 3, 1);
        Thread.sleep(300);
        mvc.perform(get("/runs/" + id)).andExpect(jsonPath("$.status").value("PENDING"));
    }

    @Test
    void leaderboardOrder() throws Exception {
        long a = submit("둘째", 5, 1);
        long b = submit("첫째", 9, 2);
        long c = submit("셋째", 5, 3);  // 둘째와 연수·진행이 같으면 먼저 올린 쪽이 위 (시드가 달라 중복은 아니다)
        waitForStatus(a);
        waitForStatus(b);
        waitForStatus(c);
        mvc.perform(get("/leaderboard"))
                .andExpect(jsonPath("$[0].playerName").value("첫째"))
                .andExpect(jsonPath("$[1].playerName").value("둘째"))
                .andExpect(jsonPath("$[2].playerName").value("셋째"));
        mvc.perform(get("/leaderboard?limit=2")).andExpect(jsonPath("$.length()").value(2));
    }

    @Test
    void duplicateSubmissionReturnsConflict() throws Exception {
        String json = body("중복", 4, 2);
        mvc.perform(post("/runs").contentType(MediaType.APPLICATION_JSON).content(json)).andExpect(status().isAccepted());
        mvc.perform(post("/runs").contentType(MediaType.APPLICATION_JSON).content(json)).andExpect(status().isConflict());
        assertThat(repository.count()).isEqualTo(1);
    }

    @Test
    void invalidRequestsAreRejected() throws Exception {
        mvc.perform(post("/runs").contentType(MediaType.APPLICATION_JSON).content("{\"playerName\": \"\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("invalid_request"));
        mvc.perform(post("/runs").contentType(MediaType.APPLICATION_JSON).content("깨진 본문"))
                .andExpect(status().isBadRequest());
        mvc.perform(post("/runs").contentType(MediaType.APPLICATION_JSON).content(body("이름이너무길어서스무글자를넘어가는플레이어", 1, 1)))
                .andExpect(status().isBadRequest());
        mvc.perform(get("/leaderboard?limit=0")).andExpect(status().isBadRequest());
        mvc.perform(get("/runs/999999")).andExpect(status().isNotFound());
    }

    // ---------- 도우미 ----------

    private long submit(String name, int years, int seed) throws Exception {
        MvcResult result = mvc.perform(post("/runs").contentType(MediaType.APPLICATION_JSON).content(body(name, years, seed)))
                .andExpect(status().isAccepted())
                .andReturn();
        return objectMapper.readTree(result.getResponse().getContentAsString()).get("id").asLong();
    }

    private String body(String name, int years, int seed) throws Exception {
        return objectMapper.writeValueAsString(Map.of(
                "playerName", name, "seed", seed,
                "actions", List.of(Map.of("type", "draft", "index", 0), Map.of("type", "expedition", "index", years % 3)),
                "years", years, "year", 184 + years, "round", 3, "gameVersion", "0.2.0"));
    }

    /** 비동기 검증이 끝날 때까지 최대 5초 기다린다. */
    private String waitForStatus(long id) throws Exception {
        for (int i = 0; i < 50; i++) {
            JsonNode run = objectMapper.readTree(mvc.perform(get("/runs/" + id)).andReturn().getResponse().getContentAsString());
            if (!"PENDING".equals(run.get("status").asText())) {
                return run.get("status").asText();
            }
            Thread.sleep(100);
        }
        return "PENDING";
    }
}
