"""Isolated command double. Never invokes launchctl, open, or sleep."""

import json
import sys
from pathlib import Path

VPN_ID = "12345678-1234-1234-1234-123456789ABC"


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
        url = args[-1]
        if url in state.get("fail_urls", []):
            result = 7
        if url == "loon://off" and result == 0:
            state["simulated_connected"] = False
        elif url == "loon://on":
            attempt = state.get("on_attempts", 0) + 1
            state["on_attempts"] = attempt
            exit_codes = state.get("on_exit_codes", [])
            if attempt <= len(exit_codes):
                result = exit_codes[attempt - 1]
            if result == 0 and attempt not in state.get("ignored_on_attempts", []):
                state["simulated_connected"] = True
            state.setdefault("on_observations", []).append(
                {"exit": result, "connected": state.get("simulated_connected", False)}
            )
        elif url == "loon://update?sub=all" and state.get("disconnect_on_update"):
            state["simulated_connected"] = False
    elif command == "scutil":
        if args == ["--nc", "list"]:
            print(state.get("vpn_listing", '* (Connected) ' + VPN_ID +
                            ' VPN (org.example.Loon) "Renamed VPN" [VPN:org.example.Loon]'))
            result = state.get("list_exit", 0)
        elif len(args) == 3 and args[:2] == ["--nc", "status"]:
            if args[2] != VPN_ID:
                raise AssertionError("Queried an unexpected VPN service")
            responses = state.get("status_responses", [])
            index = state.get("status_reads", 0)
            response = responses[min(index, len(responses) - 1)] if responses else {
                "state": "Connected" if state.get("simulated_connected", True) else "Disconnected"
            }
            state["status_reads"] = index + 1
            print(response.get("state", "Unknown"))
            print("Extended status: PRIVATE_TEST_VALUE = must-not-print")
            result = response.get("exit", 0)
        elif len(args) == 3 and args[:2] == ["--nc", "start"]:
            if args[2] != VPN_ID:
                raise AssertionError("Started an unexpected VPN service")
            attempt = state.get("native_starts", 0) + 1
            state["native_starts"] = attempt
            codes = state.get("start_exit_codes", [])
            result = codes[attempt - 1] if attempt <= len(codes) else 0
            if result == 0 and attempt in state.get("native_connect_attempts", [1, 2]):
                state["simulated_connected"] = True
        else:
            raise AssertionError("Unexpected scutil command: " + repr(args))
    elif command == "osascript":
        source = sys.stdin.read()
        if "return identifier;" in source and "runningApplicationsWithBundleIdentifier" not in source:
            print(state.get("handler_id", "org.example.Loon"))
            result = state.get("handler_exit", 0)
        elif "runningApplicationsWithBundleIdentifier" not in source:
            raise AssertionError("Unexpected AppleScript helper")
        elif state.get("fail_hide"):
            print("Simulated hide failure", file=sys.stderr)
            result = 7
        else:
            print("hidden loon:// handler")
    elif command != "sleep":
        raise AssertionError("Unexpected command: " + command)
    state_path.write_text(json.dumps(state))
    return result


if __name__ == "__main__":
    sys.exit(main())
