#!/bin/bash
# Read-only: no keyboard input, selection writes, permission requests or developer tools.
set -euo pipefail
printf '%s\n' 'FinderWrap 分组读取检测（只读）' '请在 5 秒内回到出现故障的 Finder 图标区域，保持窗口状态，等待约 12 秒。' '检测结束后，将终端中的 JSON 结果发回；不会读取文件名或路径。' >&2
/usr/bin/osascript -l JavaScript <<'JXA'
// BEGIN TESTABLE LOGIC
function safeToken(read, identifier) {
    var result = { error: read.error, type: read.type };
    if (read.type === 'string') {
        var allowed = identifier ? ['IconView', 'ListView', 'ColumnView'].indexOf(read.value) >= 0 :
            /^AX[A-Za-z0-9]{1,80}$/.test(read.value);
        result.value = allowed ? read.value : 'other-redacted';
    }
    return result;
}

// Mirror AXAccess.elements, including its before/after count check. Never export references.
function inspectChildren(api, parent, limit, deadline) {
    var report = { limit: limit, pages: [] }, elements = [];
    function stop(reason) { report.reason = reason; return { report: report, elements: [] }; }
    function interrupted() {
        if (api.now() >= deadline) return 'probe-budget-expired';
        if (!api.front()) return 'finder-not-frontmost';
        return null;
    }
    var interruption = interrupted();
    if (interruption) return stop(interruption);
    var count = api.count(parent);
    report.countBefore = count;
    if (count.error !== 0) return stop('count-read-failed');
    if (typeof count.value !== 'number' || !isFinite(count.value) || count.value < 0 || count.value % 1 !== 0)
        return stop('count-invalid');
    if (count.value > limit) return stop('count-over-limit');
    while (elements.length < count.value) {
        interruption = interrupted();
        if (interruption) return stop(interruption);
        var requested = Math.min(20, count.value - elements.length);
        var page = api.page(parent, elements.length, requested);
        var pageReport = { offset: elements.length, requested: requested, error: page.error, type: page.type };
        report.pages.push(pageReport);
        if (page.error !== 0) return stop('page-read-failed');
        if (page.type !== 'array') return stop('page-not-array');
        pageReport.returned = page.value.length;
        if (page.value.length === 0) return stop('page-empty');
        if (page.value.length > count.value - elements.length) return stop('page-too-large');
        for (var i = 0; i < page.value.length; i++) {
            var child = page.value[i];
            if (!api.isElement(child)) return stop('child-not-element');
            for (var j = 0; j < elements.length; j++) {
                if (api.equal(child, elements[j])) return stop('duplicate-child');
            }
            elements.push(child);
        }
    }
    interruption = interrupted();
    if (interruption) return stop(interruption);
    var after = api.count(parent);
    report.countAfter = after;
    if (after.error !== 0) return stop('count-recheck-failed');
    if (after.value !== count.value) return stop('count-changed');
    report.reason = 'read-complete';
    return { report: report, elements: elements };
}

function inspectSections(api, collection, deadline) {
    var output = { sections: [] };
    var sections = inspectChildren(api, collection, 24, deadline);
    output.collection = sections.report;
    if (sections.report.reason !== 'read-complete') {
        output.blocker = 'collection-' + sections.report.reason; return output;
    }
    if (!sections.elements.length) { output.blocker = 'collection-empty'; return output; }
    for (var i = 0; i < sections.elements.length; i++) {
        if (api.now() >= deadline || !api.front()) {
            output.blocker = api.front() ? 'probe-budget-expired' : 'finder-not-frontmost'; return output;
        }
        var section = sections.elements[i];
        // Read the production guard first. Role is optional diagnostic context only.
        var subrole = safeToken(api.read(section, 'AXSubrole'), false);
        var item = { index: i, subrole: subrole };
        output.sections.push(item);
        if (subrole.error !== 0) item.reason = 'section-subrole-read-failed';
        else if (subrole.type !== 'string') item.reason = 'section-subrole-not-string';
        else if (subrole.value !== 'AXSectionList') item.reason = 'section-subrole-mismatch';
        else {
            var children = inspectChildren(api, section, 164, deadline);
            item.children = children.report;
            item.reason = children.report.reason === 'read-complete' ?
                (children.elements.length ? 'section-gates-pass-items-not-tested' : 'section-empty') :
                'section-' + children.report.reason;
        }
        if (api.now() < deadline && api.front()) item.role = safeToken(api.read(section, 'AXRole'), false);
        if (item.reason !== 'section-gates-pass-items-not-tested') {
            output.blocker = 'section-' + i + ':' + item.reason; return output;
        }
    }
    output.blocker = 'section-gates-pass-items-not-tested';
    return output;
}
// END TESTABLE LOGIC

ObjC.import('AppKit');
ObjC.import('ApplicationServices');
ObjC.import('Foundation');

function convert(raw) {
    if (raw === null || raw === undefined) return { type: 'null', value: null };
    var value = ObjC.castRefToObject(raw), type = Number($.CFGetTypeID(value));
    if (type === Number($.CFStringGetTypeID())) return { type: 'string', value: ObjC.unwrap(value) };
    if (type === Number($.AXUIElementGetTypeID())) return { type: 'element', value: value };
    if (type === Number($.CFArrayGetTypeID())) {
        var items = [], count = Number($.CFArrayGetCount(value));
        for (var i = 0; i < count; i++) items.push(ObjC.castRefToObject($.CFArrayGetValueAtIndex(value, i)));
        return { type: 'array', value: items };
    }
    return { type: 'other', value: null };
}
var nativeAPI = {
    now: function() { return Date.now(); },
    front: function() {
        var front = $.NSWorkspace.sharedWorkspace.frontmostApplication;
        return !front.isNil() && ObjC.unwrap(front.bundleIdentifier) === 'com.apple.finder';
    },
    equal: function(a, b) { return Boolean($.CFEqual(a, b)); },
    isElement: function(value) { return Number($.CFGetTypeID(value)) === Number($.AXUIElementGetTypeID()); },
    read: function(parent, attribute) {
        var ref = Ref(), error = Number($.AXUIElementCopyAttributeValue(parent, $(attribute), ref));
        var result = error === 0 ? convert(ref[0]) : { type: 'unavailable', value: null };
        result.error = error; return result;
    },
    count: function(parent) {
        var ref = Ref(), error = Number($.AXUIElementGetAttributeValueCount(parent, $('AXChildren'), ref));
        return { error: error, value: error === 0 ? Number(ref[0]) : null };
    },
    page: function(parent, offset, requested) {
        var ref = Ref(), error = Number($.AXUIElementCopyAttributeValues(parent, $('AXChildren'), offset, requested, ref));
        var result = error === 0 ? convert(ref[0]) : { type: 'unavailable', value: null };
        result.error = error; return result;
    }
};

function sample(app, timeout) {
    var start = Date.now(), result = { timeoutMS: timeout * 1000, probeBudgetMS: 1200 };
    if (!nativeAPI.front()) { result.blocker = 'finder-not-frontmost'; return result; }
    result.timeoutSetupError = Number($.AXUIElementSetMessagingTimeout($.AXUIElementCreateSystemWide(), timeout));
    if (result.timeoutSetupError !== 0) { result.blocker = 'timeout-setup-failed'; return result; }
    var focus = nativeAPI.read(app, 'AXFocusedUIElement');
    result.focusRead = { error: focus.error, type: focus.type };
    if (focus.type !== 'element') { result.blocker = 'focused-element-unavailable'; return result; }
    result.focusRole = safeToken(nativeAPI.read(focus.value, 'AXRole'), false);
    result.focusSubrole = safeToken(nativeAPI.read(focus.value, 'AXSubrole'), false);
    result.focusIdentifier = safeToken(nativeAPI.read(focus.value, 'AXIdentifier'), true);
    if (result.focusRole.value !== 'AXList' || result.focusSubrole.value !== 'AXCollectionList' ||
        result.focusIdentifier.value !== 'IconView') {
        result.blocker = 'focused-element-not-icon-collection'; return result;
    }
    result.layout = inspectSections(nativeAPI, focus.value, start + 1200);
    result.blocker = result.layout.blocker;
    result.frontIsFinderAfter = nativeAPI.front();
    var after = nativeAPI.read(app, 'AXFocusedUIElement');
    result.sameFocusAfter = after.type === 'element' && nativeAPI.equal(after.value, focus.value);
    if (!result.frontIsFinderAfter || !result.sameFocusAfter) result.blocker = 'focus-changed-during-sample';
    result.elapsedMS = Date.now() - start;
    return result;
}

function run() {
    var output = { probe: 'finder-sections', probeVersion: 1, mirrorsSectionGuardIn: '1.0.1/1.0.2', readOnly: true,
        keyboardEventsSent: false, selectionWrites: false, permissionRequests: false,
        os: ObjC.unwrap($.NSProcessInfo.processInfo.operatingSystemVersionString),
        probeAccessibility: Boolean($.AXIsProcessTrusted()),
        note: 'Only AX roles, whitelisted identifiers, counts, errors and timings. No filenames, titles, paths or input text. Probe permission is separate from FinderWrap permission.' };
    if (!output.probeAccessibility) {
        output.status = 'probe-accessibility-unavailable-no-permission-requested'; return JSON.stringify(output, null, 2);
    }
    var finders = $.NSRunningApplication.runningApplicationsWithBundleIdentifier('com.apple.finder');
    if (Number(finders.count) === 0) { output.status = 'finder-not-running'; return JSON.stringify(output, null, 2); }
    var finder = finders.objectAtIndex(0), bundle = $.NSBundle.bundleWithURL(finder.bundleURL);
    output.finderVersion = ObjC.unwrap(bundle.objectForInfoDictionaryKey('CFBundleShortVersionString'));
    var app = $.AXUIElementCreateApplication(finder.processIdentifier);
    delay(5);
    output.samples = [];
    for (var i = 0; i < 4; i++) {
        output.samples.push(sample(app, i < 2 ? 0.01 : 0.05));
        if (i < 3) delay(0.4);
    }
    output.status = 'section-diagnostic-only-not-navigation-verification';
    return JSON.stringify(output, null, 2);
}
JXA
