package game.samgukji.server.verify;

/** 기록 검증기. 실제 구현은 Godot 헤드리스를 실행하는 GodotRunVerifier이고, 테스트에서는 가짜로 바꿔 끼운다. */
public interface RunVerifier {

    VerificationResult verify(VerificationRequest request);
}
