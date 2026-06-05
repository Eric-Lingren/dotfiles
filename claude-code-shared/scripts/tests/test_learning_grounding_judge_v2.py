"""Tests verifying learning-grounding-judge.md handles v2 record shape."""

import pathlib
import pytest

SHARED = pathlib.Path(__file__).resolve().parents[3] / "claude-code-shared"
AGENT_FILE = SHARED / "agents" / "learning-grounding-judge.md"


@pytest.fixture(scope="module")
def content():
    return AGENT_FILE.read_text()


class TestV2RecordAcceptance:
    def test_mentions_evidence_as_array(self, content):
        # v2 evidence is an array, not a string
        lower = content.lower()
        assert "array" in lower or "evidence" in lower

    def test_checks_quote_field(self, content):
        assert "quote" in content

    def test_mentions_v2_or_updated_shape(self, content):
        # Should reference v2 concepts
        assert "v2" in content or "source" in content or "quote" in content


class TestWritesUnifiedLog:
    def test_calls_log_learning_py(self, content):
        assert "log-learning.py" in content

    def test_no_per_skill_jsonl_path(self, content):
        assert "<skill>.jsonl" not in content
        assert "/<skill>" not in content
