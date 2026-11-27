"""Behavioral tests for the seedbox quota guard."""

import json
import tempfile
import unittest
from pathlib import Path

try:
    import ultra_media_space_guard as guard
except ModuleNotFoundError as error:
    if error.name != "ultra_media_space_guard":
        raise
    guard = None


PAUSE_AT = 3_800_000_000_000
RESUME_BELOW = 3_500_000_000_000


def torrent(hash_string, status, complete):
    return {
        "download_id": hash_string,
        "status": status,
        "candidate": {"complete": complete},
    }


def initial_state():
    return {
        "version": 1,
        "active": False,
        "paused_hashes": [],
        "pause_events_total": 0,
        "resume_events_total": 0,
        "probe_failures_total": 0,
        "rpc_failures_total": 0,
    }


class FakeTransmissionRPC:
    def __init__(self, torrents):
        self.torrents = torrents
        self.stopped = []
        self.started = []

    def get_torrents(self):
        return self.torrents

    def stop_torrents(self, hashes):
        self.stopped.append(list(hashes))

    def start_torrents(self, hashes):
        self.started.append(list(hashes))


class FailingTransmissionRPC(FakeTransmissionRPC):
    def __init__(self, torrents, failure):
        super().__init__(torrents)
        self.failure = failure

    def get_torrents(self):
        if self.failure == "get":
            raise RuntimeError("synthetic RPC failure")
        return super().get_torrents()

    def stop_torrents(self, hashes):
        if self.failure == "stop":
            raise RuntimeError("synthetic RPC failure")
        super().stop_torrents(hashes)

    def start_torrents(self, hashes):
        if self.failure == "start":
            raise RuntimeError("synthetic RPC failure")
        super().start_torrents(hashes)


class SpaceGuardPolicyTests(unittest.TestCase):
    def require_function(self, name):
        self.assertIsNotNone(guard, "quota guard module has not been implemented")
        if guard is None:
            return None
        function = getattr(guard, name, None)
        self.assertTrue(callable(function), f"quota guard must expose {name}")
        return function if callable(function) else None

    def plan(self, used_bytes, torrents, state):
        planner = self.require_function("plan_guard_actions")
        if planner is None:
            return None
        return planner(
            used_bytes,
            torrents,
            state,
            pause_at_bytes=PAUSE_AT,
            resume_below_bytes=RESUME_BELOW,
        )

    def test_high_quota_pauses_only_incomplete_active_or_queued_downloads(self):
        first = "A" * 40
        second = "B" * 40
        decision = self.plan(
            PAUSE_AT,
            [
                torrent(first, 4, False),
                torrent(second, 3, False),
                torrent("C" * 40, 6, True),
                torrent("D" * 40, 5, True),
                torrent("E" * 40, 0, False),
                torrent("F" * 40, 4, True),
                torrent("7" * 40, 4.0, False),
            ],
            initial_state(),
        )

        if decision is None:
            return
        self.assertEqual(
            decision,
            {
                "active": True,
                "paused_hashes": [first, second],
                "pause_hashes": [first, second],
                "resume_hashes": [],
            },
        )

    def test_guard_holds_in_hysteresis_band_and_catches_new_downloads(self):
        first = "A" * 40
        second = "B" * 40
        state = initial_state() | {"active": True, "paused_hashes": [first]}
        decision = self.plan(
            3_600_000_000_000,
            [
                torrent(first, 0, False),
                torrent(second, 3, False),
                torrent("C" * 40, 6, True),
            ],
            state,
        )

        if decision is None:
            return
        self.assertEqual(
            decision,
            {
                "active": True,
                "paused_hashes": [first, second],
                "pause_hashes": [second],
                "resume_hashes": [],
            },
        )

    def test_guard_resumes_only_owned_hashes_below_low_threshold(self):
        first = "A" * 40
        missing = "B" * 40
        decision = self.plan(
            RESUME_BELOW - 1,
            [torrent(first, 0, False), torrent("C" * 40, 0, False)],
            initial_state() | {"active": True, "paused_hashes": [first, missing]},
        )

        if decision is None:
            return
        self.assertEqual(
            decision,
            {
                "active": False,
                "paused_hashes": [],
                "pause_hashes": [],
                "resume_hashes": [first],
            },
        )

    def test_unknown_usage_never_resumes_guard_owned_torrents(self):
        first = "A" * 40
        decision = self.plan(
            None,
            [torrent(first, 0, False)],
            initial_state() | {"active": True, "paused_hashes": [first]},
        )

        if decision is None:
            return
        self.assertEqual(
            decision,
            {
                "active": True,
                "paused_hashes": [first],
                "pause_hashes": [],
                "resume_hashes": [],
            },
        )

    def test_guard_does_not_enter_before_the_pause_threshold(self):
        decision = self.plan(
            PAUSE_AT - 1,
            [torrent("A" * 40, 4, False)],
            initial_state(),
        )

        if decision is None:
            return
        self.assertEqual(
            decision,
            {
                "active": False,
                "paused_hashes": [],
                "pause_hashes": [],
                "resume_hashes": [],
            },
        )

    def test_guard_does_not_resume_at_the_low_watermark_boundary(self):
        first = "A" * 40
        decision = self.plan(
            RESUME_BELOW,
            [torrent(first, 0, False)],
            initial_state() | {"active": True, "paused_hashes": [first]},
        )

        if decision is None:
            return
        self.assertEqual(
            decision,
            {
                "active": True,
                "paused_hashes": [first],
                "pause_hashes": [],
                "resume_hashes": [],
            },
        )

    def test_guard_rejects_inverted_thresholds(self):
        planner = self.require_function("plan_guard_actions")
        if planner is None:
            return
        with self.assertRaises(ValueError):
            planner(
                PAUSE_AT,
                [],
                initial_state(),
                pause_at_bytes=RESUME_BELOW,
                resume_below_bytes=PAUSE_AT,
            )

    def test_invalid_thresholds_are_rejected_before_probe_or_rpc(self):
        runner = self.require_function("run_guard_cycle")
        if runner is None:
            return
        calls = []

        def quota_probe():
            calls.append("quota")
            return {"used_bytes": PAUSE_AT}

        rpc = FakeTransmissionRPC([])
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                runner(
                    quota_probe,
                    rpc,
                    Path(directory) / "state.json",
                    Path(directory) / "guard.prom",
                    pause_at_bytes=RESUME_BELOW,
                    resume_below_bytes=PAUSE_AT,
                    sample_timestamp_seconds=1_800_000_000,
                )
        self.assertEqual(calls, [])
        self.assertEqual(rpc.stopped, [])
        self.assertEqual(rpc.started, [])

    def test_corrupt_state_is_not_treated_as_resumable(self):
        loader = self.require_function("load_guard_state")
        if loader is None:
            return
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "guard-state.json"
            for contents in (
                "{not-json",
                json.dumps(initial_state() | {"version": True}),
                json.dumps(initial_state() | {"paused_hashes": ["not-a-hash"]}),
            ):
                state_path.write_text(contents, encoding="utf-8")
                with self.subTest(contents=contents):
                    self.assertIsNone(loader(state_path))

    def test_run_cycle_persists_pause_and_resumes_below_low_watermark(self):
        runner = self.require_function("run_guard_cycle")
        if runner is None:
            return
        first = "A" * 40
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state_path = root / "state.json"
            metrics_path = root / "guard.prom"
            rpc = FakeTransmissionRPC([torrent(first, 4, False)])
            result = runner(
                lambda: {"used_bytes": PAUSE_AT},
                rpc,
                state_path,
                metrics_path,
                pause_at_bytes=PAUSE_AT,
                resume_below_bytes=RESUME_BELOW,
                sample_timestamp_seconds=1_800_000_000,
            )

            self.assertTrue(result["active"])
            self.assertEqual(rpc.stopped, [[first]])
            self.assertEqual(json.loads(state_path.read_text())["paused_hashes"], [first])
            metrics = metrics_path.read_text(encoding="ascii")
            self.assertIn("ultra_seedbox_download_guard_used_bytes 3800000000000", metrics)
            self.assertIn("ultra_seedbox_download_guard_active 1", metrics)
            self.assertNotIn(first, metrics)

            rpc.torrents = [torrent(first, 0, False)]
            result = runner(
                lambda: {"used_bytes": RESUME_BELOW - 1},
                rpc,
                state_path,
                metrics_path,
                pause_at_bytes=PAUSE_AT,
                resume_below_bytes=RESUME_BELOW,
                sample_timestamp_seconds=1_800_000_060,
            )
            self.assertFalse(result["active"])
            self.assertEqual(rpc.started, [[first]])

    def test_rpc_query_failure_never_resumes_owned_hashes(self):
        runner = self.require_function("run_guard_cycle")
        writer = self.require_function("save_guard_state")
        if runner is None or writer is None:
            return
        first = "A" * 40
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state_path = root / "state.json"
            metrics_path = root / "guard.prom"
            writer(state_path, initial_state() | {"active": True, "paused_hashes": [first]})
            rpc = FailingTransmissionRPC([torrent(first, 0, False)], "get")
            result = runner(
                lambda: {"used_bytes": RESUME_BELOW - 1},
                rpc,
                state_path,
                metrics_path,
                pause_at_bytes=PAUSE_AT,
                resume_below_bytes=RESUME_BELOW,
                sample_timestamp_seconds=1_800_000_000,
            )
            state = json.loads(state_path.read_text())
            self.assertEqual(result["status"], "rpc_failed")
            self.assertEqual(rpc.started, [])
            self.assertTrue(state["active"])
            self.assertEqual(state["paused_hashes"], [first])
            self.assertEqual(state["rpc_failures_total"], 1)

    def test_failed_stop_keeps_the_guard_active_and_owns_the_target_hash(self):
        runner = self.require_function("run_guard_cycle")
        if runner is None:
            return
        first = "A" * 40
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state_path = root / "state.json"
            metrics_path = root / "guard.prom"
            rpc = FailingTransmissionRPC([torrent(first, 4, False)], "stop")
            result = runner(
                lambda: {"used_bytes": PAUSE_AT},
                rpc,
                state_path,
                metrics_path,
                pause_at_bytes=PAUSE_AT,
                resume_below_bytes=RESUME_BELOW,
                sample_timestamp_seconds=1_800_000_000,
            )
            state = json.loads(state_path.read_text())
            self.assertEqual(result["status"], "rpc_failed")
            self.assertTrue(state["active"])
            self.assertEqual(state["paused_hashes"], [first])
            self.assertEqual(state["rpc_failures_total"], 1)

    def test_failed_resume_keeps_the_guard_state_for_retry(self):
        runner = self.require_function("run_guard_cycle")
        writer = self.require_function("save_guard_state")
        if runner is None or writer is None:
            return
        first = "A" * 40
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state_path = root / "state.json"
            metrics_path = root / "guard.prom"
            writer(state_path, initial_state() | {"active": True, "paused_hashes": [first]})
            rpc = FailingTransmissionRPC([torrent(first, 0, False)], "start")
            result = runner(
                lambda: {"used_bytes": RESUME_BELOW - 1},
                rpc,
                state_path,
                metrics_path,
                pause_at_bytes=PAUSE_AT,
                resume_below_bytes=RESUME_BELOW,
                sample_timestamp_seconds=1_800_000_000,
            )
            state = json.loads(state_path.read_text())
            self.assertEqual(result["status"], "rpc_failed")
            self.assertTrue(state["active"])
            self.assertEqual(state["paused_hashes"], [first])
            self.assertEqual(state["rpc_failures_total"], 1)

    def test_corrupted_state_prevents_all_rpc_actions(self):
        runner = self.require_function("run_guard_cycle")
        if runner is None:
            return
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state_path = root / "state.json"
            state_path.write_text("{broken", encoding="utf-8")
            rpc = FakeTransmissionRPC([torrent("A" * 40, 0, False)])
            result = runner(
                lambda: {"used_bytes": RESUME_BELOW - 1},
                rpc,
                state_path,
                root / "guard.prom",
                pause_at_bytes=PAUSE_AT,
                resume_below_bytes=RESUME_BELOW,
                sample_timestamp_seconds=1_800_000_000,
            )
            self.assertEqual(result["status"], "state_invalid")
            self.assertEqual(rpc.started, [])
            self.assertEqual(rpc.stopped, [])

    def test_run_cycle_probe_failure_never_starts_guard_owned_torrents(self):
        runner = self.require_function("run_guard_cycle")
        writer = self.require_function("save_guard_state")
        if runner is None or writer is None:
            return
        first = "A" * 40
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state_path = root / "state.json"
            metrics_path = root / "guard.prom"
            writer(state_path, initial_state() | {"active": True, "paused_hashes": [first]})
            rpc = FakeTransmissionRPC([torrent(first, 0, False)])
            result = runner(
                lambda: None,
                rpc,
                state_path,
                metrics_path,
                pause_at_bytes=PAUSE_AT,
                resume_below_bytes=RESUME_BELOW,
                sample_timestamp_seconds=1_800_000_000,
            )
            self.assertEqual(rpc.started, [])
            self.assertTrue(result["active"])
            self.assertEqual(json.loads(state_path.read_text())["paused_hashes"], [first])


if __name__ == "__main__":
    unittest.main(verbosity=2)
