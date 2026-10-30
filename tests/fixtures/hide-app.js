// Run the embedded helper against a fake AppKit bridge, never the actual desktop.
function run() {
    var clock = 0;
    var requested = [];
    var handler = testCase.bundleId || "org.example.Loon";
    var models = testCase.apps || [];
    var instances = models.map(function (model) {
        var app = {};
        model.hidden = Boolean(model.hidden);
        Object.defineProperty(app, "isHidden", {get: function () { return model.hidden; }});
        Object.defineProperty(app, "isTerminated", {get: function () { return Boolean(model.terminated); }});
        Object.defineProperty(app, "hide", {get: function () {
            requested.push(model.pid);
            if (model.refuseHide) return false;
            model.pending = true;
            return !model.falseReturn;
        }});
        return app;
    });
    var fakeBridge = {
        NSURL: {URLWithString: function (value) {
            if (value !== "loon://") throw new Error("Unexpected URL lookup");
            return value;
        }},
        NSWorkspace: {sharedWorkspace: {URLForApplicationToOpenURL: function () {
            return testCase.registered === false ? undefined : {application: handler};
        }}},
        NSBundle: {bundleWithURL: function (url) {
            return {bundleIdentifier: url ? url.application : undefined};
        }},
        NSRunningApplication: {runningApplicationsWithBundleIdentifier: function (identifier) {
            if (identifier !== handler) throw new Error("Unexpected bundle identifier");
            var matching = instances.filter(function (_, index) {
                return (models[index].bundleId || handler) === handler;
            });
            return {count: matching.length, objectAtIndex: function (index) { return matching[index]; }};
        }},
        NSDate: {dateWithTimeIntervalSinceNow: function (seconds) { return clock + seconds * 1000; }},
        NSRunLoop: {currentRunLoop: {runUntilDate: function (deadline) {
            clock = deadline;
            models.forEach(function (model) {
                if (model.pending && !model.neverHide) model.hidden = true;
            });
        }}}
    };
    var fakeObjC = {
        import: function (name) { if (name !== "AppKit") throw new Error("Unexpected framework"); },
        unwrap: function (value) { return value; }
    };
    var value, error;
    try {
        value = Function("ObjC", "$", "Date", helperSource + "\nreturn run();")(
            fakeObjC, fakeBridge, {now: function () { return clock; }}
        );
    } catch (failure) {
        error = String(failure);
    }
    return JSON.stringify({value: value, error: error, requested: requested, apps: models, clock: clock});
}
