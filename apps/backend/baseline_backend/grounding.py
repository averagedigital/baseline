from __future__ import annotations

import re
from dataclasses import dataclass


REFERENCE = re.compile(r"\[(ev|food|model):([^\]]+)\]")


@dataclass(frozen=True)
class GroundingResult:
    valid: bool
    issues: list[str]


def verify_grounding(
    markdown: str,
    *,
    evidence_ids: set[str],
    food_ids: set[str],
    model_ids: set[str],
) -> GroundingResult:
    issues: list[str] = []
    allowed = {"ev": evidence_ids, "food": food_ids, "model": model_ids}
    for line_number, line in enumerate(markdown.splitlines(), start=1):
        references = REFERENCE.findall(line)
        for kind, value in references:
            if value not in allowed[kind]:
                issues.append(f"line {line_number}: unknown [{kind}:{value}]")
        text_without_refs = REFERENCE.sub("", line)
        has_exact_number = any(character.isdigit() for character in text_without_refs)
        if has_exact_number and not references:
            issues.append(f"line {line_number}: exact number without evidence reference")
    return GroundingResult(valid=not issues, issues=issues)
