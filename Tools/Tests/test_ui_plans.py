"""Protect the native CI partition against missing, duplicate or disabled flows."""
import argparse
import json
from pathlib import Path
import re
import unittest
import sys
import uuid
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FOCUSED = {
    "MosslingUITests/testActivityLibraryAddsDistinctSnackAndPersistsSelection()",
    "MosslingUITests/testEarnedAffinityCanBeSelectedAndChanged()",
}
PERSISTENCE = {
    "MosslingUITests/testCompletedSnackEarnsGrowthOnceAndSurvivesRelaunch()",
    "MosslingUITests/testActivityEditorCreatesAndUpdatesSnack()",
}
PLAN_NAMES = ("All", "Focused", "Persistence", "Remainder")


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


def validate_focused_result_file(path, identifier):
    prefix = "MosslingUITests/"
    if not identifier.startswith(prefix) or identifier[len(prefix):] + "()" not in discover_tests():
        raise ValueError(f"Unknown UI test method: {identifier}")
    validate_result_summary(json.loads(path.read_text()), 1)
    print(f"{identifier}: passed; no skipped tests (focused development run, not full acceptance)")


class UITestPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plans = {
            name: json.loads((ROOT / f"Config/Tests/{name}.xctestplan").read_text())
            for name in PLAN_NAMES
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
        all_tests, focused, persistence, remainder = [self.plans[n]["testTargets"][0] for n in PLAN_NAMES]
        self.assertEqual(set(all_tests), {"target", "parallelizable"})
        self.assertEqual(set(focused), {"target", "parallelizable", "selectedTests"})
        self.assertEqual(set(persistence), {"target", "parallelizable", "selectedTests"})
        self.assertEqual(set(remainder), {"target", "parallelizable", "skippedTests"})
        self.assertEqual(set(focused["selectedTests"]), FOCUSED)
        self.assertEqual(len(focused["selectedTests"]), len(FOCUSED))
        self.assertEqual(set(persistence["selectedTests"]), PERSISTENCE)
        self.assertEqual(len(persistence["selectedTests"]), len(PERSISTENCE))
        self.assertEqual(set(remainder["skippedTests"]), FOCUSED | PERSISTENCE)
        self.assertEqual(len(remainder["skippedTests"]), len(FOCUSED | PERSISTENCE))
        current = discover_tests()
        self.assertGreaterEqual(len(current), 7, "Existing acceptance flows must remain")
        self.assertLessEqual(FOCUSED | PERSISTENCE, current, "A renamed selected test would silently drop coverage")
        for universe in (current, current | {"MosslingUITests/testFutureFlow()", "NewFeatureTests/testFutureSuite()"}):
            self.assertEqual(selected(all_tests, universe), universe)
            partitions = [selected(target, universe) for target in (focused, persistence, remainder)]
            self.assertEqual(set.union(*partitions), universe)
            self.assertEqual(sum(map(len, partitions)), len(universe), "No flow may run twice")

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
            f"Config/Tests/{name}.xctestplan" for name in PLAN_NAMES
        ])

    def test_focused_result_requires_a_real_method_and_one_complete_pass(self):
        identifier = "MosslingUITests/" + sorted(discover_tests())[0].removesuffix("()")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "summary.json"
            passing = {"totalTestCount": 1, "passedTests": 1, "failedTests": 0,
                       "skippedTests": 0, "expectedFailures": 0}
            path.write_text(json.dumps(passing))
            validate_focused_result_file(path, identifier)
            for invalid in (identifier + "Typo", "MosslingUITests/MosslingUITests", identifier + "/extra"):
                with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                    validate_focused_result_file(path, invalid)
            path.write_text(json.dumps(dict(passing, totalTestCount=0, passedTests=0)))
            with self.assertRaises(ValueError):
                validate_focused_result_file(path, identifier)

    def test_ci_runs_every_partition_and_requires_its_result(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        ui_job = re.search(r"^  ui:\n(.*?)(?=^  \w+:|\Z)", workflow, re.M | re.S)
        self.assertIsNotNone(ui_job)
        matrix = re.search(r"^        plan: \[([^\]]+)\]$", ui_job[1], re.M)
        self.assertIsNotNone(matrix)
        self.assertEqual([name.strip() for name in matrix[1].split(",")], list(PLAN_NAMES[1:]))
        verify_job = re.search(r"^  verify:\n(.*)", workflow, re.M | re.S)
        self.assertIsNotNone(verify_job)
        self.assertRegex(verify_job[1], r"needs: \[[^\]]*\bui\b[^\]]*\]")
        self.assertIn('test "${{ needs.ui.result }}" = success', verify_job[1])


if __name__ == "__main__":
    if "--result-summary" in sys.argv:
        parser = argparse.ArgumentParser(description="Require native UI results to cover the selected test plan")
        parser.add_argument("--result-summary", type=Path, required=True)
        selection = parser.add_mutually_exclusive_group(required=True)
        selection.add_argument("--plan", choices=PLAN_NAMES)
        selection.add_argument("--test", help="One target/suite/method for a focused development run")
        args = parser.parse_args()
        try:
            if args.test:
                validate_focused_result_file(args.result_summary, args.test)
            else:
                validate_result_file(args.result_summary, args.plan)
        except (OSError, ValueError, KeyError) as error:
            parser.exit(1, f"UI result validation failed: {error}\n")
    else:
        unittest.main()
