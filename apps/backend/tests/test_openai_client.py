from baseline_backend.openai_client import OpenAIResponsesClient


def test_extracts_responses_output_text() -> None:
    payload = {
        "output": [
            {
                "type": "message",
                "content": [
                    {"type": "output_text", "text": '{"answer_markdown":"ok","recommendation_category":"none"}'}
                ],
            }
        ]
    }
    assert OpenAIResponsesClient._extract_output_text(payload).startswith("{")
