from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path
from typing import Any

from Scripts.Quality import validate_schemas

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "support_report_binding.json"


def load_fixture() -> dict[str, Any]:
    with FIXTURE.open(encoding="utf-8") as source:
        return json.load(source)


class ReportSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.documents = validate_schemas.validate_schema_documents()
        self.registry = validate_schemas.schema_registry(self.documents)
        self.validator = validate_schemas.Draft202012Validator(
            self.documents["report.schema.json"],
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )

    def test_accepts_a_report_with_a_bound_controller_and_a_rejected_candidate(
        self,
    ) -> None:
        report = load_fixture()
        controller = report["data"]["controllers"][0]
        self.assertTrue(controller["binding"]["interfaces"])
        unbound = report["data"]["unboundDevices"][0]
        self.assertTrue(unbound["binding"]["rejectedCandidates"])

        self.validator.validate(report)

    def test_rejects_a_top_level_catalog_record_id_on_an_unsupported_result(
        self,
    ) -> None:
        report = copy.deepcopy(load_fixture())
        report["data"]["unboundDevices"][0]["binding"]["catalogRecordID"] = "045e-02d1"

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def test_rejects_a_rejected_candidate_without_a_reason(self) -> None:
        report = copy.deepcopy(load_fixture())
        candidate = report["data"]["unboundDevices"][0]["binding"][
            "rejectedCandidates"
        ][0]
        del candidate["reason"]

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)


if __name__ == "__main__":
    unittest.main()
