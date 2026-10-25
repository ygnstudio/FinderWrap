#!/bin/bash
# Portable, read-only diagnostic. No developer tools, AX writes or permission prompts.
set -euo pipefail
printf '%s\n' 'FinderWrap read-only check. No developer tools required.' 'Within 5 seconds, switch to the affected Finder surface and leave it as it was when wrapping failed.' 'Keep Finder in front until the check finishes (usually 10 seconds total).' >&2
/usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
ObjC.import('ApplicationServices');
ObjC.import('Foundation');

function read(element, attribute) {
    if (!element) return { error: null, type: 'not-read', value: null };
    var ref = Ref();
    var error = Number($.AXUIElementCopyAttributeValue(element, $(attribute), ref));
    if (error !== 0) return { error: error, type: 'unavailable', value: null };
    // JXA exposes an out CFTypeRef as an opaque pointer; casting is required before inspecting it.
    var value = ObjC.castRefToObject(ref[0]);
    var typeID = Number($.CFGetTypeID(value));
    var type = typeID === Number($.AXUIElementGetTypeID()) ? 'element' :
        typeID === Number($.CFStringGetTypeID()) ? 'string' :
        typeID === Number($.CFArrayGetTypeID()) ? 'array' : 'other';
    return { error: 0, type: type, value: value };
}

function element(result) { return result.type === 'element' ? result.value : null; }
function status(result) { return { error: result.error, type: result.type }; }
function equal(a, b) { return a && b ? Boolean($.CFEqual(a, b)) : null; }
function token(result, identifiersOnly) {
    var output = status(result);
    if (result.type !== 'string') return output;
    var value = ObjC.unwrap(result.value);
    var allowed = identifiersOnly ? ['IconView', 'ListView', 'ColumnView', 'FinderWindow'].indexOf(value) >= 0 :
        /^AX[A-Za-z0-9]{1,80}$/.test(value);
    output.value = allowed ? value : 'other-redacted';
    return output;
}
function frontIsFinder() {
    var front = $.NSWorkspace.sharedWorkspace.frontmostApplication;
    return !front.isNil() && ObjC.unwrap(front.bundleIdentifier) === 'com.apple.finder';
}

// Bounded role-only structure snapshot. Never read AXTitle, AXValue, AXURL or AXDescription.
function structure(app) {
    var started = Date.now(), deadline = started + 1500;
    var result = { nodes: [], roots: {}, limitNodes: 100, limitDepth: 7, limitChildren: 24,
        budgetMS: 1500, truncated: false, frontIsFinderBefore: frontIsFinder() };
    if (!result.frontIsFinderBefore) { result.status = 'finder-not-frontmost'; return result; }
    $.AXUIElementSetMessagingTimeout($.AXUIElementCreateSystemWide(), 0.05);
    var elements = [], depths = [];
    function register(item, depth) {
        if (!item) return null;
        for (var i = 0; i < elements.length; i++) if (equal(item, elements[i])) return i;
        if (elements.length >= result.limitNodes || depth > result.limitDepth) { result.truncated = true; return null; }
        elements.push(item); depths.push(depth);
        return elements.length - 1;
    }
    function boundedRead(item, attribute) {
        if (Date.now() >= deadline) { result.truncated = true; return {error: null, type: 'budget-exhausted', value: null}; }
        return read(item, attribute);
    }
    ['AXMainWindow', 'AXFocusedWindow', 'AXFocusedUIElement'].forEach(function(attribute) {
        var root = boundedRead(app, attribute);
        result.roots[attribute] = { read: status(root), node: register(element(root), 0) };
    });
    for (var index = 0; index < elements.length && Date.now() < deadline; index++) {
        if (!frontIsFinder()) { result.status = 'focus-changed-during-structure'; break; }
        var item = elements[index];
        var node = { id: index, depth: depths[index], role: token(boundedRead(item, 'AXRole')),
            subrole: token(boundedRead(item, 'AXSubrole')),
            identifier: token(boundedRead(item, 'AXIdentifier'), true), children: [] };
        var count = Ref();
        if (Date.now() < deadline) {
            node.selectedChildrenError = Number($.AXUIElementGetAttributeValueCount(item, $('AXSelectedChildren'), count));
            if (node.selectedChildrenError === 0) node.selectedChildrenCount = Number(count[0]);
        }
        var children = boundedRead(item, 'AXChildren');
        node.childrenRead = status(children);
        if (children.type === 'array') {
            node.childCount = Number($.CFArrayGetCount(children.value));
            var limit = Math.min(node.childCount, result.limitChildren);
            if (limit < node.childCount) result.truncated = true;
            for (var child = 0; child < limit && Date.now() < deadline; child++) {
                var value = ObjC.castRefToObject($.CFArrayGetValueAtIndex(children.value, child));
                if (Number($.CFGetTypeID(value)) === Number($.AXUIElementGetTypeID())) {
                    var id = register(value, depths[index] + 1);
                    if (id !== null) node.children.push(id);
                }
            }
        }
        result.nodes.push(node);
    }
    result.frontIsFinderAfter = frontIsFinder();
    result.elapsedMS = Date.now() - started;
    if (result.nodes.length < elements.length || result.elapsedMS >= 1500) result.truncated = true;
    if (!result.status) result.status = result.frontIsFinderAfter ? 'sampled-role-structure' : 'focus-changed-during-structure';
    return result;
}

function sample(app, timeout) {
    var result = { timeoutSeconds: timeout, frontIsFinderBefore: frontIsFinder() };
    if (!result.frontIsFinderBefore) { result.blocker = 'finder-not-frontmost'; return result; }
    var started = Date.now();
    result.timeoutSetupError = Number($.AXUIElementSetMessagingTimeout($.AXUIElementCreateSystemWide(), timeout));
    var main = read(app, 'AXMainWindow');
    var focused = read(app, 'AXFocusedWindow');
    var mainElement = element(main), focusedElement = element(focused);
    var mainRole = token(read(mainElement, 'AXRole'));
    var mainSubrole = token(read(mainElement, 'AXSubrole'));
    var focusedRole = token(read(focusedElement, 'AXRole'));
    var focusedSubrole = token(read(focusedElement, 'AXSubrole'));
    var focus = read(app, 'AXFocusedUIElement');
    var focusElement = element(focus);
    var focusRole = token(read(focusElement, 'AXRole'));
    var focusSubrole = token(read(focusElement, 'AXSubrole'));
    var focusIdentifier = token(read(focusElement, 'AXIdentifier'), true);
    var owner = read(focusElement, 'AXWindow');
    var parent = read(focusElement, 'AXParent');
    var parentRole = token(read(element(parent), 'AXRole'));
    result.mainWindow = status(main);
    result.focusedWindow = status(focused);
    result.mainEqualsFocused = equal(mainElement, focusedElement);
    result.mainRole = mainRole;
    result.mainSubrole = mainSubrole;
    result.focusedRole = focusedRole;
    result.focusedSubrole = focusedSubrole;
    result.focus = { attribute: status(focus), role: focusRole, subrole: focusSubrole,
        identifier: focusIdentifier, owner: status(owner),
        ownerEqualsMain: equal(element(owner), mainElement),
        parent: status(parent), parentRole: parentRole };
    result.frontIsFinderAfter = frontIsFinder();
    result.elapsedMS = Date.now() - started;
    // Mirror 1.0.1's gate order, but report each refusal separately.
    if (!result.frontIsFinderAfter) result.blocker = 'focus-changed-during-sample';
    else if (!mainElement) result.blocker = 'main-window-unavailable';
    else if (!focusedElement) result.blocker = 'focused-window-unavailable';
    else if (!result.mainEqualsFocused) result.blocker = 'main-focused-window-mismatch';
    else if (mainSubrole.value !== 'AXStandardWindow') result.blocker = 'main-window-subrole-not-standard';
    else if (!focusElement) result.blocker = 'focused-element-unavailable';
    else if (focusRole.value !== 'AXList') result.blocker = 'focus-role-not-list';
    else if (focusSubrole.value !== 'AXCollectionList') result.blocker = 'focus-subrole-not-collection';
    else if (focusIdentifier.value !== 'IconView') result.blocker = 'focus-identifier-not-icon-view';
    else if (!result.focus.ownerEqualsMain) result.blocker = 'collection-owner-mismatch-or-unavailable';
    else if (parentRole.value !== 'AXScrollArea') result.blocker = 'scroll-parent-unavailable-or-different';
    else result.blocker = 'initial-window-and-focus-gates-pass-layout-not-tested';
    return result;
}

function run() {
    var output = { probeVersion: 1, readOnly: true, keyboardEventsSent: false,
        selectionWrites: false, permissionRequests: false,
        os: ObjC.unwrap($.NSProcessInfo.processInfo.operatingSystemVersionString),
        probeAccessibility: Boolean($.AXIsProcessTrusted()),
        note: 'Probe permission is separate from FinderWrap permission. No filenames, window titles, file paths or input text are collected.' };
    if (!output.probeAccessibility) {
        output.status = 'probe-accessibility-unavailable-no-permission-requested';
        return JSON.stringify(output, null, 2);
    }
    var finders = $.NSRunningApplication.runningApplicationsWithBundleIdentifier('com.apple.finder');
    if (Number(finders.count) === 0) {
        output.status = 'finder-not-running';
        return JSON.stringify(output, null, 2);
    }
    var finder = finders.objectAtIndex(0);
    var bundle = $.NSBundle.bundleWithURL(finder.bundleURL);
    output.finderVersion = ObjC.unwrap(bundle.objectForInfoDictionaryKey('CFBundleShortVersionString'));
    var app = $.AXUIElementCreateApplication(finder.processIdentifier);
    delay(5);
    output.samples = [];
    // First three use 1.0.1's 10 ms per-call timeout; the last three are a 50 ms control.
    // This does not run the app's 150 ms whole-layout scan or change its timeouts.
    for (var i = 0; i < 6; i++) {
        output.samples.push(sample(app, i < 3 ? 0.01 : 0.05));
        if (i < 5) delay(0.4);
    }
    output.structure = structure(app);
    output.status = 'sampled-window-gates-and-role-structure-not-navigation-verification';
    return JSON.stringify(output, null, 2);
}
JXA
