"""Isolated command double. Never invokes launchctl, open, or sleep."""

import json
import sys
from pathlib import Path


def main():
    state_path = Path(sys.argv[1])
    command, *args = sys.argv[2:]
    state = json.loads(state_path.read_text())
    state.setdefault("calls", []).append([command, *args])
    result = 0
    if command == "launchctl":
        action = args[0]
        if action == "print":
            if args[1].count("/") == 1:
                result = 0 if state.get("gui", True) else 113
            elif not state.get("loaded", False):
                result = 113
            else:
                print("test job = {")
                print("\tactive count = {}".format(int(state.get("running", False))))
                print("\tstate = {}".format("running" if state.get("running") else "not running"))
                print("\truns = {}".format(state.get("runs", 0)))
                print("\tlast exit code = 0")
                print("\trun interval = 21600 seconds")
                print("\tenvironment = { PRIVATE_TEST_VALUE = must-not-print }")
                if state.get("running"):
                    print("\tpid = 12345")
                print("}")
        elif action == "enable":
            state["disabled"] = False
        elif action == "disable":
            state["disabled"] = True
        elif action == "bootstrap":
            if state.get("fail_bootstrap"):
                print("Simulated bootstrap failure", file=sys.stderr)
                result = 5
            else:
                state["loaded"] = True
        elif action == "bootout":
            if state.get("running"):
                raise AssertionError("Tried to stop an active reconnect cycle")
            state["loaded"] = False
        elif action == "kickstart":
            if "-k" in args:
                raise AssertionError("Forced kickstart is forbidden")
            state["runs"] = state.get("runs", 0) + 1
        else:
            raise AssertionError("Unexpected launchctl action: " + action)
    elif command == "open":
        if args[-1] in state.get("fail_urls", []):
            result = 7
    elif command != "sleep":
        raise AssertionError("Unexpected command: " + command)
    state_path.write_text(json.dumps(state))
    return result


if __name__ == "__main__":
    sys.exit(main())
