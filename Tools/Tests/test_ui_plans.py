"""Protect the native CI partition against missing, duplicate or disabled flows."""
import argparse
import json
from pathlib import Path
import re
import unittest
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
FOCUSED = {
    "MosslingUITests/testEarnedAffinityChoicePersistsAndCanBeChanged()",
}


def discover_tests():
    tests = set()
    for path in (ROOT / "Apps/UITests").glob("**/*.swift"):
        suite = None
        for line in path.read_text().splitlines():
            declaration = re.search(r"\bclass\s+(\w+)\s*:", line)
            if declaration:
                suite = declaration[1]
            method = re.search(r"\bfunc\s+(test\w+)\s*\(\s*\)", line)
            if method:
                assert suite, f"Test method without a suite in {path}"
                tests.add(f"{suite}/{method[1]}()")
    return tests


def selected(target, universe):
    return (set(target.get("selectedTests", universe)) & universe) - set(target.get("skippedTests", []))


def validate_result_summary(summary, expected):
    # Native xcresulttool test-results summary schema; require every counter so
    # absent/malformed results cannot become a green zero-test run.
    # Reference implementation: getsentry/XcodeBuildMCP v1.12.0,
    # src/utils/test-common.ts (TestSummary and parseXcresultBundle).
    counts = {"totalTestCount": expected, "passedTests": expected,
              "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
    if not isinstance(summary, dict) or expected <= 0:
        raise ValueError("Missing native summary or empty expected test selection")
    for key, wanted in counts.items():
        if type(summary.get(key)) is not int or summary[key] != wanted:
            raise ValueError(f"Native result {key}: expected {wanted}, received {summary.get(key)!r}")


def validate_result_file(path, plan_name):
    plan = json.loads((ROOT / f"Config/Tests/{plan_name}.xctestplan").read_text())
    expected = len(selected(plan["testTargets"][0], discover_tests()))
    validate_result_summary(json.loads(path.read_text()), expected)
    print(f"{plan_name}: all {expected} expected UI tests passed; none skipped")


class UITestPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plans = {
            name: json.loads((ROOT / f"Config/Tests/{name}.xctestplan").read_text())
            for name in ("All", "Focused", "Remainder")
        }

    def test_target_identity_and_execution_options(self):
        project = (ROOT / "Mossling.xcodeproj/project.pbxproj").read_text()
        match = re.search(r"([A-F0-9]{24}) /\* MosslingUITests \*/ = \{\s*isa = PBXNativeTarget;", project)
        self.assertIsNotNone(match, "UI target must exist in the generated project")
        for name, plan in self.plans.items():
            with self.subTest(plan=name):
                self.assertEqual(set(plan), {"configurations", "defaultOptions", "testTargets", "version"})
                self.assertEqual(plan["version"], 1)
                self.assertEqual(plan["defaultOptions"], {"codeCoverage": False, "mainThreadCheckerEnabled": True})
                self.assertEqual(len(plan["configurations"]), 1, "No duplicated configuration runs")
                config = plan["configurations"][0]
                self.assertEqual(set(config), {"id", "name", "options"})
                uuid.UUID(config["id"])
                self.assertEqual(config["name"], "Default")
                self.assertEqual(config["options"], {}, "No hidden configuration overrides")
                self.assertEqual(len(plan["testTargets"]), 1)
                target = plan["testTargets"][0]
                self.assertIs(target["parallelizable"], False)
                self.assertEqual(target["target"], {
                    "containerPath": "container:Mossling.xcodeproj",
                    "identifier": match[1], "name": "MosslingUITests",
                })

    def test_exact_complement_without_extra_filters(self):
        all_tests, focused, remainder = [self.plans[n]["testTargets"][0] for n in ("All", "Focused", "Remainder")]
        self.assertEqual(set(all_tests), {"target", "parallelizable"})
        self.assertEqual(set(focused), {"target", "parallelizable", "selectedTests"})
        self.assertEqual(set(remainder), {"target", "parallelizable", "skippedTests"})
        self.assertEqual(set(focused["selectedTests"]), FOCUSED)
        self.assertEqual(len(focused["selectedTests"]), len(FOCUSED))
        self.assertEqual(set(remainder["skippedTests"]), FOCUSED)
        self.assertEqual(len(remainder["skippedTests"]), len(FOCUSED))
        current = discover_tests()
        self.assertGreaterEqual(len(current), 7, "Existing acceptance flows must remain")
        self.assertLessEqual(FOCUSED, current, "A renamed focused test would silently drop coverage")
        for universe in (current, current | {"MosslingUITests/testFutureFlow()", "NewFeatureTests/testFutureSuite()"}):
            self.assertEqual(selected(all_tests, universe), universe)
            self.assertFalse(selected(focused, universe) & selected(remainder, universe))
            self.assertEqual(selected(focused, universe) | selected(remainder, universe), universe)

    def test_native_result_gate_rejects_missing_failed_skipped_and_zero_tests(self):
        passing = {"totalTestCount": 2, "passedTests": 2, "failedTests": 0,
                   "skippedTests": 0, "expectedFailures": 0}
        validate_result_summary(passing, 2)
        for field in passing:
            missing = dict(passing)
            del missing[field]
            with self.subTest(missing=field), self.assertRaises(ValueError):
                validate_result_summary(missing, 2)
            wrong = dict(passing, **{field: passing[field] + 1})
            with self.subTest(wrong=field), self.assertRaises(ValueError):
                validate_result_summary(wrong, 2)
            wrong_type = dict(passing, **{field: str(passing[field])})
            with self.subTest(type=field), self.assertRaises(ValueError):
                validate_result_summary(wrong_type, 2)
        for summary in ({}, None, [], dict(passing, totalTestCount=0, passedTests=0),
                        dict(passing, skippedTests=True)):
            with self.subTest(summary=summary), self.assertRaises(ValueError):
                validate_result_summary(summary, 2)
        with self.assertRaises(ValueError):
            validate_result_summary(passing, 0)

    def test_all_is_the_default_scheme_plan(self):
        manifest = (ROOT / "Project.swift").read_text()
        action = re.search(r"testAction:\s*\.testPlans\(\s*\[(.*?)\],", manifest, re.S)
        self.assertIsNotNone(action)
        self.assertEqual(re.findall(r'\.path\("([^"]+)"\)', action[1]), [
            "Config/Tests/All.xctestplan", "Config/Tests/Focused.xctestplan", "Config/Tests/Remainder.xctestplan",
        ])


if __name__ == "__main__":
    if "--result-summary" in sys.argv:
        parser = argparse.ArgumentParser(description="Require native UI results to cover the selected test plan")
        parser.add_argument("--result-summary", type=Path, required=True)
        parser.add_argument("--plan", choices=("All", "Focused", "Remainder"), required=True)
        args = parser.parse_args()
        try:
            validate_result_file(args.result_summary, args.plan)
        except (OSError, ValueError, KeyError) as error:
            parser.exit(1, f"UI result validation failed: {error}\n")
    else:
        unittest.main()
