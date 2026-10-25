"""Exercise the shipped read-only probe without Finder, permissions or UI input."""
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts/diagnose-finder-sections.command"
LOGIC = SCRIPT.read_text().split("// BEGIN TESTABLE LOGIC\n", 1)[1].split("// END TESTABLE LOGIC", 1)[0]
HARNESS = """
function node(children, subrole) {
    return {isElement: true, children: children || [], subrole: subrole || 'AXSectionList'};
}
var section = node([node(), node()]);
var collection = node([section]);
var api = {
    now: function() { return 0; }, front: function() { return true; },
    equal: function(a,b) { return a === b; },
    isElement: function(a) { return !!a && a.isElement === true; },
    count: function(a) { return {error: 0, value: a.children.length}; },
    page: function(a,offset,n) { return {error: 0, type: 'array', value: a.children.slice(offset,offset+n)}; },
    read: function(a,attr) { return {error: 0, type: 'string', value: attr === 'AXSubrole' ? a.subrole : 'AXList'}; }
};
"""


class SectionProbeTests(unittest.TestCase):
    def evaluate(self, setup="", expression="inspectChildren(api, section, 164, 1200).report"):
        result = subprocess.run(
            ["/usr/bin/osascript", "-l", "JavaScript"],
            input=LOGIC + HARNESS + setup + "\nJSON.stringify(" + expression + ");\n",
            text=True, capture_output=True, check=True,
        )
        return json.loads(result.stdout)

    def test_success_is_not_claimed_as_navigation_verification(self):
        result = self.evaluate(expression="inspectSections(api, collection, 1200)")
        self.assertEqual(result["blocker"], "section-gates-pass-items-not-tested")
        self.assertEqual(result["sections"][0]["children"]["countAfter"]["value"], 2)

    def test_section_subrole_failures_remain_distinguishable(self):
        cases = [
            ("section.subrole='AXUnknown';", "section-subrole-mismatch"),
            ("api.read=function(){return {error:-25204,type:'unavailable',value:null};};", "section-subrole-read-failed"),
            ("api.read=function(){return {error:0,type:'other',value:null};};", "section-subrole-not-string"),
            ("section.children=[];", "section-empty"),
        ]
        for setup, reason in cases:
            with self.subTest(reason=reason):
                result = self.evaluate(setup, "inspectSections(api, collection, 1200)")
                self.assertEqual(result["blocker"], "section-0:" + reason)

    def test_count_failure_and_recheck_failure(self):
        result = self.evaluate("api.count=function(){return {error:-25202,value:null};};")
        self.assertEqual(result["reason"], "count-read-failed")
        self.assertEqual(result["countBefore"]["error"], -25202)
        self.assertEqual(result["pages"], [])
        result = self.evaluate("var calls=0; api.count=function(){return ++calls===1 ? {error:0,value:2} : {error:-25204,value:null};};")
        self.assertEqual(result["reason"], "count-recheck-failed")

    def test_invalid_and_excessive_count_does_not_fetch_children(self):
        for value, reason in ((-1, "count-invalid"), (1.5, "count-invalid"), (165, "count-over-limit")):
            with self.subTest(value=value):
                result = self.evaluate("api.count=function(){return {error:0,value:" + str(value) + "};}; api.page=function(){throw Error('must not fetch');};")
                self.assertEqual(result["reason"], reason)
                self.assertEqual(result["pages"], [])

    def test_limit_boundary_uses_pagination_and_rechecks_count(self):
        result = self.evaluate("section.children=[]; for(var i=0;i<164;i++) section.children.push(node());")
        self.assertEqual(result["reason"], "read-complete")
        self.assertEqual([p["offset"] for p in result["pages"]], list(range(0, 164, 20)))
        self.assertEqual(result["pages"][-1]["requested"], 4)
        self.assertEqual(result["countAfter"]["value"], 164)

    def test_all_page_refusals_have_distinct_codes(self):
        cases = [
            ("{error:-25204,type:'unavailable',value:null}", "page-read-failed"),
            ("{error:0,type:'null',value:null}", "page-not-array"),
            ("{error:0,type:'array',value:[]}", "page-empty"),
            ("{error:0,type:'array',value:[node(),node(),node()]}", "page-too-large"),
            ("{error:0,type:'array',value:['private-filename']}", "child-not-element"),
            ("{error:0,type:'array',value:[section,section]}", "duplicate-child"),
        ]
        for page, reason in cases:
            with self.subTest(reason=reason):
                result = self.evaluate("api.page=function(){return " + page + ";};")
                self.assertEqual(result["reason"], reason)
                self.assertNotIn("private-filename", json.dumps(result))

    def test_count_change_is_not_a_successful_snapshot(self):
        result = self.evaluate("var calls=0; api.count=function(){return {error:0,value:++calls===1?2:3};};")
        self.assertEqual(result["reason"], "count-changed")

    def test_budget_and_frontmost_guards_stop_before_reading(self):
        for setup, reason in (("api.now=function(){return 1200;};", "probe-budget-expired"),
                              ("api.front=function(){return false;};", "finder-not-frontmost")):
            with self.subTest(reason=reason):
                result = self.evaluate(setup + "api.count=function(){throw Error('must not read');};")
                self.assertEqual(result["reason"], reason)

    def test_budget_and_focus_change_stop_pagination(self):
        for mutation, reason in (("api.now=function(){return 1200;};", "probe-budget-expired"),
                                 ("api.front=function(){return false;};", "finder-not-frontmost")):
            with self.subTest(reason=reason):
                result = self.evaluate("section.children=[];for(var i=0;i<21;i++)section.children.push(node());var original=api.page;api.page=function(a,o,n){" + mutation + "return original(a,o,n);};")
                self.assertEqual(result["reason"], reason)
                self.assertEqual(len(result["pages"]), 1)

    def test_collection_limit_is_reported_before_section_inspection(self):
        result = self.evaluate("collection.children=[];for(var i=0;i<25;i++)collection.children.push(node());",
                               "inspectSections(api, collection, 1200)")
        self.assertEqual(result["blocker"], "collection-count-over-limit")
        self.assertEqual(result["sections"], [])

    def test_role_and_identifier_redaction_has_positive_controls(self):
        for value, identifier, expected in (("AXSectionList", False, "AXSectionList"),
                                            ("IconView", True, "IconView"),
                                            ("/Users/private/report.txt", False, "other-redacted"),
                                            ("private-window-id", True, "other-redacted")):
            with self.subTest(value=value):
                result = self.evaluate(expression="safeToken({error:0,type:'string',value:" + json.dumps(value) + "}," + json.dumps(identifier) + ")")
                self.assertEqual(result["value"], expected)

    def test_probe_limits_and_paging_stay_aligned_with_production(self):
        source = (ROOT / "FinderWrap/Core/FinderAccessibility.swift").read_text()
        maximum = int(re.search(r"static let maximumItems = (\d+)", source)[1])
        result = self.evaluate(expression="inspectSections(api, collection, 1200)")
        self.assertEqual(result["collection"]["limit"], 24)
        self.assertIn("limit: 24", source)
        self.assertEqual(result["sections"][0]["children"]["limit"], maximum + 4)
        self.assertIn("min(20, total - result.count)", (ROOT / "FinderWrap/Core/FinderContext.swift").read_text())


if __name__ == "__main__":
    unittest.main()
