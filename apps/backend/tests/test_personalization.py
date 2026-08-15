from baseline_backend.personalization import OnlinePersonalizer


def test_difficulty_model_learns_only_after_explicit_labels() -> None:
    model = OnlinePersonalizer()
    features = [1.0, 0.7, 0.5, 0.4, 0.9, 0.6, 0.5, 0.3]
    state = None

    assert model.predict(state, features).predicted_difficulty is None
    for _ in range(5):
        state = model.update_difficulty(state, features, 8.0)

    prediction = model.predict(state, features)
    assert prediction.predicted_difficulty is not None
    assert prediction.predicted_difficulty > 6.5
    assert prediction.confidence == 0.25


def test_bandit_reward_changes_selected_category() -> None:
    model = OnlinePersonalizer(alpha=0.01)
    features = [1.0, 0.7, 0.5, 0.4, 0.9, 0.6, 0.5, 0.3]
    state = None
    for _ in range(8):
        state = model.update_reward(state, features, "recovery", 1.0)
        state = model.update_reward(state, features, "load", -1.0)

    assert model.predict(state, features).suggested_action == "recovery"
