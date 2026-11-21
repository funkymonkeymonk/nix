"""Synthetic tests for the Ultra.cc retention policy evaluator."""

import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from contextlib import contextmanager, nullcontext, redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import urlsplit


POLICY_PATH = Path(sys.argv.pop(1))
ADAPTER_PATH = Path(sys.argv.pop(1))
STAGING_PATH = Path(sys.argv.pop(1))
SCRIPT_DIR = Path(sys.argv.pop(1))
sys.path.insert(0, str(SCRIPT_DIR))
os.environ["PYTHONPATH"] = os.pathsep.join(
    filter(None, [str(SCRIPT_DIR), os.environ.get("PYTHONPATH", "")])
)
import ultra_media_file_stat as file_stat
spec = importlib.util.spec_from_file_location("ultra_media_cleanup", POLICY_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load retention policy module")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)
adapter_spec = importlib.util.spec_from_file_location("transmission_rpc", ADAPTER_PATH)
if adapter_spec is None or adapter_spec.loader is None:
    raise RuntimeError("could not load Transmission RPC adapter module")
transmission_rpc = importlib.util.module_from_spec(adapter_spec)
adapter_spec.loader.exec_module(transmission_rpc)
staging_spec = importlib.util.spec_from_file_location("ultra_media_download_stage", STAGING_PATH)
if staging_spec is None or staging_spec.loader is None:
    raise RuntimeError("could not load download staging module")
staging = importlib.util.module_from_spec(staging_spec)
staging_spec.loader.exec_module(staging)


def load_sync_module():
    sync_path = SCRIPT_DIR / "ultra-media-sync.py"
    spec = importlib.util.spec_from_file_location("ultra_media_sync", sync_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load unified sync module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(spec.name, None)
        raise
    return module


class FakeRPCResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


class FakeTransmissionRPCServer:
    """In-memory opener for exercising the RPC contract without network I/O."""

    def __init__(self, rpc_version=17):
        self.rpc_version = rpc_version
        self.requests = []
        self.request_count = 0
        self.url = "https://rpc.example.test/transmission/rpc"

    def open(self, request, timeout=20):
        request_url = request.full_url
        if urlsplit(request_url).scheme != "https":
            raise AssertionError("fake RPC opener refuses non-HTTPS requests")
        self.request_count += 1
        payload = json.loads(request.data)
        session_id = next(
            (value for name, value in request.header_items() if name.lower() == "x-transmission-session-id"),
            None,
        )
        self.requests.append(
            {
                "method": payload["method"],
                "arguments": payload.get("arguments", {}),
                "session_id": session_id,
                "scheme": urlsplit(request_url).scheme,
            }
        )
        if not session_id:
            raise HTTPError(
                request_url,
                409,
                "synthetic session negotiation",
                {"X-Transmission-Session-Id": "fake-session-token"},
                io.BytesIO(),
            )

        if payload["method"] == "session-get":
            arguments = {"version": "test-version", "rpc-version": self.rpc_version}
            response = {"result": "success", "arguments": arguments}
        elif payload["method"] == "torrent-get":
            if getattr(self, "api_error", False):
                response = {"result": "synthetic error detail", "arguments": {}}
            else:
                torrent = {
                    "id": 17,
                    "status": 6,
                    "doneDate": 1_700_000_000,
                    "secondsSeeding": 86400,
                    "uploadRatio": 2.5,
                    "trackers": [
                        {"id": 4, "announce": "https://tracker.example.test/announce", "tier": 0}
                    ],
                    "files": [
                        {"name": "Season 1/episode 01.mkv", "length": 1024, "bytesCompleted": 1024}
                    ],
                }
                if self.rpc_version >= 4:
                    torrent["downloadDir"] = "/seedbox/complete"
                if self.rpc_version >= 5:
                    torrent.update({"leftUntilDone": 0, "percentDone": 1.0})
                if self.rpc_version < 7:
                    torrent["trackers"].append(
                        {"id": 5, "announce": "https://tracker-two.example.test/announce", "tier": 1}
                    )
                if self.rpc_version >= 7:
                    torrent["trackerStats"] = [
                        {
                            "id": 4,
                            "host": "tracker.example.test",
                            "announceState": 6,
                            "lastAnnounceSucceeded": True,
                        }
                    ]
                else:
                    torrent.update(
                        {
                            "announceURL": "https://tracker.example.test/announce",
                            "announceResponse": "ok",
                        }
                    )
                if self.rpc_version >= 9:
                    torrent["isFinished"] = getattr(self, "is_finished", True)
                arguments = {"torrents": [torrent]}
                response = {"result": "success", "arguments": arguments}
        elif payload["method"] == "torrent-remove":
            response = {"result": "success", "arguments": {}}
        else:
            raise AssertionError("unexpected RPC operation")
        return FakeRPCResponse(json.dumps(response).encode())

    def close(self):
        pass


class TransmissionRPCTests(unittest.TestCase):
    def setUp(self):
        self.server = FakeTransmissionRPCServer()
        self.opener_patcher = patch.object(
            transmission_rpc,
            "build_opener",
            side_effect=lambda *_args, **_kwargs: self.server,
        )
        self.opener_patcher.start()
        self.client = transmission_rpc.TransmissionRPC(
            self.server.url, username="test-user", password="test-password"
        )

    def tearDown(self):
        self.opener_patcher.stop()

    def test_get_normalizes_deployed_torrent_metadata(self):
        torrents = self.client.get_torrents()
        self.assertEqual(len(torrents), 1)
        torrent = torrents[0]
        self.assertEqual(torrent["id"], 17)
        self.assertEqual(torrent["done_date"], 1_700_000_000)
        self.assertTrue(torrent["candidate"]["complete"])
        self.assertEqual(torrent["candidate"]["seeding_seconds"], 86400)
        self.assertEqual(torrent["candidate"]["torrent_ratio"], 2.5)
        self.assertEqual(torrent["download_directory"], "/seedbox/complete")
        self.assertEqual(torrent["file_paths"], ["Season 1/episode 01.mkv"])
        self.assertEqual(torrent["file_sizes"], [1024])
        self.assertEqual(torrent["tracker_states"], [{"host": "tracker.example.test", "announce_state": 6}])
        self.assertEqual(torrent["candidate"]["trackers"], [{"classification": "unknown"}])
        self.assertEqual(
            torrent["candidate"]["files"],
            [
                {
                    "mapped": False,
                    "source_mapping_verified": False,
                    "source_identity": None,
                    "source_ownership_verified": False,
                    "source_owner_count": None,
                    "local_match": False,
                    "shared_safe": False,
                }
            ],
        )

    def test_complete_download_facts_override_false_is_finished_seed_state(self):
        self.server.is_finished = False
        torrent = self.client.get_torrents()[0]
        self.assertTrue(torrent["candidate"]["complete"])

    def test_is_finished_does_not_override_incomplete_payload_facts(self):
        torrent = transmission_rpc.normalize_torrent(
            {
                "id": 18,
                "status": 0,
                "doneDate": 0,
                "isFinished": True,
                "leftUntilDone": 1,
                "percentDone": 0.99,
                "secondsSeeding": 0,
                "uploadRatio": 0.0,
                "trackers": [],
                "files": [],
            }
        )
        self.assertFalse(torrent["candidate"]["complete"])
        self.assertIsNone(torrent["done_date"])

    def test_normalized_torrent_ignores_invalid_completion_timestamps(self):
        for timestamp in (None, 0, -1, True, "1700000000"):
            with self.subTest(timestamp=timestamp):
                torrent = transmission_rpc.normalize_torrent(
                    {
                        "id": 19,
                        "status": 6,
                        "doneDate": timestamp,
                        "secondsSeeding": 0,
                        "uploadRatio": 0.0,
                        "trackers": [],
                        "files": [],
                    }
                )
                self.assertIsNone(torrent["done_date"])

    def test_http_rpc_endpoint_is_rejected_before_opener_creation(self):
        with patch.object(transmission_rpc, "build_opener") as build_opener:
            with self.assertRaises(ValueError):
                transmission_rpc.TransmissionRPC(
                    "http://rpc.example.test/transmission/rpc",
                    username="test-user",
                    password="test-password",
                )
            build_opener.assert_not_called()

    def test_basic_auth_credentials_are_scoped_to_https_endpoint(self):
        rpc_url = "https://rpc.example.test/transmission/rpc"
        with patch.object(transmission_rpc, "HTTPPasswordMgrWithDefaultRealm") as manager_type:
            with patch.object(transmission_rpc, "build_opener"):
                transmission_rpc.TransmissionRPC(
                    rpc_url, username="test-user", password="test-password"
                )
        manager_type.return_value.add_password.assert_called_once_with(
            None, rpc_url, "test-user", "test-password"
        )

    def test_reads_use_session_token_and_never_issue_remove_request(self):
        self.client.get_torrents()
        self.assertGreaterEqual(self.server.request_count, 3)
        self.assertTrue(all(request["scheme"] == "https" for request in self.server.requests))
        self.assertEqual(
            [request["method"] for request in self.server.requests],
            ["session-get", "session-get", "torrent-get"],
        )
        self.assertEqual(
            [request["session_id"] for request in self.server.requests],
            [None, "fake-session-token", "fake-session-token"],
        )
        self.assertNotIn("torrent-remove", [request["method"] for request in self.server.requests])

    def test_rejects_non_read_rpc_operations_before_sending_them(self):
        with self.assertRaises(transmission_rpc.TransmissionRPCError):
            self.client._rpc("torrent-remove", {"ids": [17]})
        self.assertEqual(self.server.requests, [])

    def test_remove_torrent_requests_both_torrent_and_seedbox_payload_removal(self):
        self.client.remove_torrent(17, delete_local_data=True)

        request = self.server.requests[-1]
        self.assertEqual(request["method"], "torrent-remove")
        self.assertEqual(
            request["arguments"],
            {"ids": [17], "delete-local-data": True},
        )
        self.assertEqual(request["session_id"], "fake-session-token")

    def test_remove_torrent_refuses_to_leave_seedbox_payload_behind(self):
        with self.assertRaises(ValueError):
            self.client.remove_torrent(17, delete_local_data=False)

    def test_remove_torrent_rejects_invalid_identifier(self):
        for torrent_id in (0, -1, True, "17"):
            with self.subTest(torrent_id=torrent_id):
                with self.assertRaises(ValueError):
                    self.client.remove_torrent(torrent_id, delete_local_data=True)

    def test_api_error_response_is_reported_without_exposing_response_detail(self):
        self.server.api_error = True
        with self.assertRaises(transmission_rpc.TransmissionRPCError) as raised:
            self.client.get_torrents()
        self.assertEqual(
            str(raised.exception),
            "Transmission RPC returned an unsuccessful response",
        )
        self.assertNotIn("synthetic error detail", str(raised.exception))

    def test_requests_only_documented_read_fields(self):
        self.client.get_torrents()
        request = next(item for item in self.server.requests if item["method"] == "torrent-get")
        self.assertNotIn("ids", request["arguments"])
        self.assertEqual(
            set(request["arguments"]["fields"]),
            {
                "id",
                "status",
                "isFinished",
                "leftUntilDone",
                "percentDone",
                "secondsSeeding",
                "doneDate",
                "uploadRatio",
                "trackers",
                "downloadDir",
                "files",
                "trackerStats",
            },
        )

    def test_rpc_version_eight_uses_legacy_completion_fields(self):
        self.server.close()
        self.server = FakeTransmissionRPCServer(rpc_version=8)
        self.client = transmission_rpc.TransmissionRPC(
            self.server.url, username="test-user", password="test-password"
        )
        torrent = self.client.get_torrents()[0]
        self.assertTrue(torrent["candidate"]["complete"])
        request = next(item for item in self.server.requests if item["method"] == "torrent-get")
        self.assertNotIn("isFinished", request["arguments"]["fields"])
        self.assertIn("trackerStats", request["arguments"]["fields"])

    def test_rpc_version_six_uses_documented_legacy_tracker_fields(self):
        self.server.close()
        self.server = FakeTransmissionRPCServer(rpc_version=6)
        self.client = transmission_rpc.TransmissionRPC(
            self.server.url, username="test-user", password="test-password"
        )
        torrent = self.client.get_torrents()[0]
        request = next(item for item in self.server.requests if item["method"] == "torrent-get")
        fields = set(request["arguments"]["fields"])
        self.assertIn("announceURL", fields)
        self.assertIn("announceResponse", fields)
        self.assertNotIn("trackerStats", fields)
        self.assertIn("downloadDir", fields)
        self.assertEqual(
            torrent["tracker_states"],
            [
                {"host": "tracker.example.test", "announce_state": "reported"},
                {"host": "tracker-two.example.test", "announce_state": "not_reported"},
            ],
        )
        self.assertTrue(torrent["candidate"]["complete"])

    def test_tracker_without_announce_host_is_unknown(self):
        torrent = transmission_rpc.normalize_torrent(
            {
                "id": 1,
                "status": 6,
                "isFinished": True,
                "leftUntilDone": 0,
                "percentDone": 1.0,
                "secondsSeeding": 100,
                "uploadRatio": 3.0,
                "trackerStats": [{"announceState": 6}],
                "downloadDir": "/seedbox/complete",
                "files": [{"name": "payload.bin"}],
            },
            tracker_classifier=lambda _host: "public",
        )
        self.assertEqual(torrent["candidate"]["trackers"], [{"classification": "unknown"}])


class RetentionPolicyTests(unittest.TestCase):
    def candidate(self, **overrides):
        candidate = {
            "complete": True,
            "done_date": 1_700_000_000,
            "torrent_ratio": 0.0,
            "trackers": [{"classification": "public"}],
            "files": [
                {
                    "mapped": True,
                    "source_mapping_verified": True,
                    "source_identity": "fixture-source-identity",
                    "source_ownership_verified": True,
                    "source_owner_count": 1,
                    "local_match": True,
                    "shared_safe": True,
                }
            ],
        }
        candidate.update(overrides)
        return candidate

    def test_qualifies_by_done_date_age_even_when_transmission_reports_no_seeding_time(self):
        now_seconds = 1_800_000_000
        with patch.object(policy.time, "time", return_value=now_seconds):
            decision = policy.evaluate_retention(
                self.candidate(
                    done_date=now_seconds - 240 * 60 * 60,
                    seeding_seconds=0,
                    torrent_ratio=0.1,
                )
            )
        self.assertTrue(decision["eligible"])

    def test_missing_done_date_fails_closed_when_ratio_is_below_threshold(self):
        with patch.object(policy.time, "time", return_value=1_800_000_000):
            decision = policy.evaluate_retention(
                self.candidate(done_date=None, torrent_ratio=2.99)
            )
        self.assertFalse(decision["eligible"])
        self.assertIn("completion_time_unknown", decision["reasons"])

    def test_qualifies_at_exact_completion_age_with_low_ratio(self):
        now_seconds = 1_800_000_000
        with patch.object(policy.time, "time", return_value=now_seconds):
            decision = policy.evaluate_retention(
                self.candidate(
                    done_date=now_seconds - 240 * 60 * 60,
                    torrent_ratio=0.1,
                )
            )
        self.assertTrue(decision["eligible"])

    def test_qualifies_at_exact_torrent_ratio_even_when_recently_completed(self):
        now_seconds = 1_800_000_000
        with patch.object(policy.time, "time", return_value=now_seconds):
            decision = policy.evaluate_retention(
                self.candidate(done_date=now_seconds - 1, torrent_ratio=3.0)
            )
        self.assertTrue(decision["eligible"])

    def test_mapped_file_requires_explicit_verified_source_provenance(self):
        for provenance in (None, False):
            with self.subTest(provenance=provenance):
                file_record = {
                    "mapped": True,
                    "local_match": True,
                    "shared_safe": True,
                }
                if provenance is not None:
                    file_record["source_mapping_verified"] = provenance
                decision = policy.evaluate_retention(
                    self.candidate(
                        seeding_seconds=240 * 60 * 60,
                        files=[file_record],
                    )
                )
                self.assertFalse(decision["eligible"])
                self.assertIn("source_mapping_unverified", decision["reasons"])

    def test_source_ownership_must_be_verified_and_unique(self):
        cases = [
            ({"source_ownership_verified": False, "source_owner_count": 1}, "source_ownership_unverified"),
            ({"source_ownership_verified": True, "source_owner_count": 2}, "source_file_shared"),
        ]
        for ownership, expected_reason in cases:
            with self.subTest(ownership=ownership):
                candidate = self.candidate(seeding_seconds=240 * 60 * 60)
                candidate["files"][0].update(ownership)
                decision = policy.evaluate_retention(candidate)
                self.assertFalse(decision["eligible"])
                self.assertIn(expected_reason, decision["reasons"])

    def test_fully_verified_source_mapping_and_ownership_can_qualify(self):
        decision = policy.evaluate_retention(
            self.candidate(
                seeding_seconds=240 * 60 * 60,
                files=[
                    {
                        "mapped": True,
                        "source_mapping_verified": True,
                        "source_identity": "fixture-unique-source",
                        "source_ownership_verified": True,
                        "source_owner_count": 1,
                        "local_match": True,
                        "shared_safe": True,
                    }
                ],
            )
        )
        self.assertTrue(decision["eligible"])

    def test_below_both_retention_limits_does_not_qualify(self):
        now_seconds = 1_800_000_000
        with patch.object(policy.time, "time", return_value=now_seconds):
            decision = policy.evaluate_retention(
                self.candidate(
                    done_date=now_seconds - (240 * 60 * 60) + 1,
                    torrent_ratio=2.99,
                )
            )
        self.assertFalse(decision["eligible"])
        self.assertIn("below_retention_threshold", decision["reasons"])

    def test_incomplete_torrent_never_qualifies(self):
        decision = policy.evaluate_retention(
            self.candidate(complete=False, seeding_seconds=240 * 60 * 60, torrent_ratio=4.0)
        )
        self.assertFalse(decision["eligible"])
        self.assertIn("incomplete_torrent", decision["reasons"])

    def test_public_tracker_does_not_need_account_ratio_lookup(self):
        decision = policy.evaluate_retention(
            self.candidate(
                seeding_seconds=240 * 60 * 60,
                trackers=[{"classification": "public"}],
            )
        )
        self.assertTrue(decision["eligible"])

    def test_private_tracker_passes_at_exact_account_ratio_floor(self):
        decision = policy.evaluate_retention(
            self.candidate(
                seeding_seconds=240 * 60 * 60,
                trackers=[
                    {
                        "classification": "private",
                        "ratio_source_available": True,
                        "account_ratio": 0.6,
                    }
                ],
            )
        )
        self.assertTrue(decision["eligible"])

    def test_private_tracker_below_account_ratio_floor_blocks(self):
        decision = policy.evaluate_retention(
            self.candidate(
                seeding_seconds=240 * 60 * 60,
                trackers=[
                    {
                        "classification": "private",
                        "ratio_source_available": True,
                        "account_ratio": 0.59,
                    }
                ],
            )
        )
        self.assertFalse(decision["eligible"])
        self.assertIn("private_ratio_below_floor", decision["reasons"])

    def test_unknown_tracker_classification_blocks(self):
        decision = policy.evaluate_retention(
            self.candidate(
                seeding_seconds=240 * 60 * 60,
                trackers=[{"classification": "unknown"}],
            )
        )
        self.assertFalse(decision["eligible"])
        self.assertIn("tracker_classification_unknown", decision["reasons"])

    def test_missing_private_ratio_blocks(self):
        decision = policy.evaluate_retention(
            self.candidate(
                seeding_seconds=240 * 60 * 60,
                trackers=[
                    {"classification": "private", "ratio_source_available": True}
                ],
            )
        )
        self.assertFalse(decision["eligible"])
        self.assertIn("private_ratio_missing", decision["reasons"])

    def test_malformed_private_ratio_blocks(self):
        decision = policy.evaluate_retention(
            self.candidate(
                seeding_seconds=240 * 60 * 60,
                trackers=[
                    {
                        "classification": "private",
                        "ratio_source_available": True,
                        "account_ratio": "not-a-number",
                    }
                ],
            )
        )
        self.assertFalse(decision["eligible"])
        self.assertIn("private_ratio_malformed", decision["reasons"])

    def test_unavailable_private_ratio_source_blocks(self):
        decision = policy.evaluate_retention(
            self.candidate(
                seeding_seconds=240 * 60 * 60,
                trackers=[
                    {
                        "classification": "private",
                        "ratio_source_available": False,
                        "account_ratio": 1.2,
                    }
                ],
            )
        )
        self.assertFalse(decision["eligible"])
        self.assertIn("private_ratio_unavailable", decision["reasons"])

    def test_missing_local_file_blocks(self):
        decision = policy.evaluate_retention(
            self.candidate(
                seeding_seconds=240 * 60 * 60,
                files=[
                    {
                        "mapped": True,
                        "source_mapping_verified": True,
                        "local_match": False,
                        "shared_safe": True,
                    }
                ],
            )
        )
        self.assertFalse(decision["eligible"])
        self.assertIn("local_file_mismatch", decision["reasons"])

    def test_unmapped_source_path_blocks(self):
        decision = policy.evaluate_retention(
            self.candidate(
                seeding_seconds=240 * 60 * 60,
                files=[
                    {
                        "mapped": False,
                        "source_mapping_verified": True,
                        "local_match": True,
                        "shared_safe": True,
                    }
                ],
            )
        )
        self.assertFalse(decision["eligible"])
        self.assertIn("file_unmapped", decision["reasons"])

    def test_unsafe_shared_file_relationship_blocks(self):
        decision = policy.evaluate_retention(
            self.candidate(
                seeding_seconds=240 * 60 * 60,
                files=[
                    {
                        "mapped": True,
                        "source_mapping_verified": True,
                        "local_match": True,
                        "shared_safe": False,
                    }
                ],
            )
        )
        self.assertFalse(decision["eligible"])
        self.assertIn("shared_file_unsafe", decision["reasons"])

    def test_absent_payload_file_metadata_blocks(self):
        decision = policy.evaluate_retention(
            self.candidate(seeding_seconds=240 * 60 * 60, files=[])
        )
        self.assertFalse(decision["eligible"])
        self.assertIn("payload_files_missing", decision["reasons"])


class CleanupRuntimeTests(unittest.TestCase):
    def staged_candidate(self, staged_path, *, expected_size=1024):
        return {
            "complete": True,
            "done_date": 1_700_000_000,
            "torrent_ratio": 3.0,
            "runtime_config_available": True,
            "rpc_available": True,
            "trackers": [{"classification": "public"}],
            "files": [
                {
                    "mapped": True,
                    "source_mapping_verified": True,
                    "source_identity": "/seedbox/complete/episode.mkv",
                    "source_ownership_verified": True,
                    "source_owner_count": 1,
                    "remote_path": "/seedbox/complete/episode.mkv",
                    "staged_path": str(staged_path),
                    "expected_size": expected_size,
                    "shared_safe": True,
                }
            ],
        }

    def test_cleanup_proves_staging_without_arr_state(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging_root = Path(temporary_directory) / ".arr-staging"
            staging_root.mkdir()
            staged_file = staging_root / "episode.mkv"
            staged_file.write_bytes(b"x" * 1024)
            expected_mtime = 1_700_000_000_000_000_000
            os.utime(staged_file, ns=(expected_mtime, expected_mtime))
            candidate = self.staged_candidate(staged_file)
            source_stat = lambda _path: {
                "regular_file": True,
                "size": 1024,
                "mtime_ns": expected_mtime,
            }

            report = policy.build_cleanup_report(
                True,
                [candidate],
                staged_copy_prover=policy.make_staged_copy_prover(
                    source_stat, staging_root=str(staging_root)
                ),
                staged_file_verifier=lambda file_record: policy.verify_local_staged_file(
                    file_record, staging_root=str(staging_root)
                ),
            )

        self.assertEqual(report["eligible"], 1)
        self.assertEqual(report["reasons"], {})

    def test_staged_copy_proof_rejects_remote_size_mismatch(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging_root = Path(temporary_directory) / ".arr-staging"
            staging_root.mkdir()
            staged_file = staging_root / "episode.mkv"
            staged_file.write_bytes(b"x" * 1024)
            candidate = self.staged_candidate(staged_file)
            proof = policy.make_staged_copy_prover(
                lambda _path: {
                    "regular_file": True,
                    "size": 1023,
                    "mtime_ns": 1_700_000_000_000_000_000,
                },
                staging_root=str(staging_root),
            )(candidate)

        self.assertEqual(proof.status, "unverified")

    def test_staged_copy_proof_rejects_mtime_mismatch(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging_root = Path(temporary_directory) / ".arr-staging"
            staging_root.mkdir()
            staged_file = staging_root / "episode.mkv"
            staged_file.write_bytes(b"x" * 1024)
            os.utime(staged_file, ns=(1_700_000_000_000_000_000,) * 2)
            candidate = self.staged_candidate(staged_file)
            proof = policy.make_staged_copy_prover(
                lambda _path: {
                    "regular_file": True,
                    "size": 1024,
                    "mtime_ns": 1_700_000_000_000_000_001,
                },
                staging_root=str(staging_root),
            )(candidate)

        self.assertEqual(proof.status, "unverified")

    def test_staged_copy_proof_rejects_missing_or_symlinked_files(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            staging_root = root / ".arr-staging"
            staging_root.mkdir()
            outside_file = root / "outside.mkv"
            outside_file.write_bytes(b"x" * 1024)
            expected_mtime = 1_700_000_000_000_000_000
            os.utime(outside_file, ns=(expected_mtime, expected_mtime))
            source_stat = lambda _path: {
                "regular_file": True,
                "size": 1024,
                "mtime_ns": expected_mtime,
            }
            missing = policy.make_staged_copy_prover(
                source_stat, staging_root=str(staging_root)
            )(self.staged_candidate(staging_root / "missing.mkv"))
            symlink = staging_root / "linked.mkv"
            symlink.symlink_to(outside_file)
            linked = policy.make_staged_copy_prover(
                source_stat, staging_root=str(staging_root)
            )(self.staged_candidate(symlink))
            outside = policy.make_staged_copy_prover(
                source_stat, staging_root=str(staging_root)
            )(self.staged_candidate(outside_file))

        self.assertEqual(missing.status, "unverified")
        self.assertEqual(linked.status, "unverified")
        self.assertEqual(outside.status, "unverified")

    def test_cleanup_candidates_need_no_arr_import_path_mapping(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging_root = str(Path(temporary_directory) / ".arr-staging")
            torrent = {
                "id": 17,
                "done_date": 1_700_000_000,
                "candidate": {"complete": True, "files": [{}]},
                "download_directory": "/seedbox/complete",
                "file_paths": ["Series/episode.mkv"],
                "file_paths_valid": True,
                "file_sizes": [1024],
                "file_sizes_valid": True,
            }
            candidates = policy.build_cleanup_candidates(
                [torrent],
                [{"remoteRoot": "/seedbox/complete", "stagingSubpath": ""}],
                staging_root=staging_root,
                path_mapper=staging.map_remote_path_to_staging,
            )

        file_record = candidates[0]["files"][0]
        self.assertEqual(file_record["staged_path"], f"{staging_root}/Series/episode.mkv")
        self.assertNotIn("local_path", file_record)
        self.assertNotIn("arr_state_available", candidates[0])

    def test_stale_receipt_ack_skips_busy_torrent_without_blocking(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            queue_root = root / "cleanup-queue"
            runtime_root = root / "runtime"
            receipt = staging.write_staged_torrent_receipt(
                queue_root, 71, "f" * 64, staged_at_ns=1_000_000_000
            )

            with staging.torrent_operation_lock(runtime_root, 71):
                acknowledged = policy.ack_stale_receipt_if_unlocked(
                    staging, queue_root, runtime_root, receipt
                )
                self.assertFalse(acknowledged)
                self.assertEqual(
                    len(staging.read_pending_torrent_receipts(queue_root, now_ns=1_000_000_000)),
                    1,
                )

            self.assertTrue(
                policy.ack_stale_receipt_if_unlocked(
                    staging, queue_root, runtime_root, receipt
                )
            )
            self.assertEqual(list(queue_root.glob("*.json")), [])

    def test_runtime_module_loader_resolves_modules_from_pythonpath(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_file = root / "store-file" / "cleanup.py"
            source_file.parent.mkdir()
            source_file.write_text("", encoding="utf-8")
            scripts_dir = root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_helper.py").write_text("VALUE = 42\n", encoding="utf-8")
            module_name = "runtime_loader_fixture"
            sys.modules.pop(module_name, None)
            with patch.object(policy, "__file__", str(source_file)):
                with patch.dict("os.environ", {"PYTHONPATH": str(scripts_dir)}):
                    module = policy._load_runtime_module(module_name, "runtime_helper.py")
            try:
                self.assertEqual(module.VALUE, 42)
            finally:
                sys.modules.pop(module_name, None)

    def test_app_stats_disk_usage_parser_uses_decimal_gigabytes(self):
        output = (
            " *** disk stats ***\n"
            "                           date  value\n"
            "1413 2026-11-17 22:06:27.438047   4000.5\n"
        )

        self.assertEqual(
            file_stat.parse_app_stats_disk_usage(output),
            {"used_bytes": 4_000_500_000_000},
        )

    def test_app_stats_disk_usage_parser_fails_closed_on_missing_or_malformed_rows(self):
        for output in (
            "",
            " *** disk stats ***\n date value\n",
            "1413 2026-11-17 22:06:27.438047 NaN\n",
            "1413 2026-11-17 22:06:27.438047 -2\n",
        ):
            with self.subTest(output=output):
                self.assertIsNone(file_stat.parse_app_stats_disk_usage(output))

    def test_remote_disk_usage_probe_uses_fixed_app_stats_command_and_strict_ssh_args(self):
        commands = []
        sample = "header\n1413 2026-11-17 22:06:27.438047 4000\n"

        def runner(arguments, **kwargs):
            commands.append((arguments, kwargs))
            return SimpleNamespace(stdout=sample, returncode=0)

        probe = file_stat.make_remote_disk_usage_probe(
            ["ssh", "-o", "StrictHostKeyChecking=yes"],
            "seed-user",
            "seed.example",
            process_runner=runner,
        )

        self.assertEqual(probe(), {"used_bytes": 4_000_000_000_000})
        self.assertEqual(commands[0][0][-1], "app-stats show -s disk -t hour -c 1")
        self.assertEqual(commands[0][0][-2], "seed-user@seed.example")
        self.assertIs(commands[0][1]["stderr"], subprocess.DEVNULL)

    def test_remote_disk_usage_probe_fails_closed_without_exposing_command_output(self):
        probe = file_stat.make_remote_disk_usage_probe(
            ["ssh", "-o", "StrictHostKeyChecking=yes"],
            "seed-user",
            "seed.example",
            process_runner=lambda *_args, **_kwargs: (_ for _ in ()).throw(
                subprocess.CalledProcessError(1, ["ssh"], stderr="private diagnostic")
            ),
        )

        self.assertIsNone(probe())

    def test_runtime_remote_disk_probe_uses_scoped_strict_ssh_and_returns_only_usage(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            values = {
                "ssh_host": "seed.example.test",
                "ssh_username": "seed-user",
                "known_hosts": "seed.example.test ssh-ed25519 fixture",
            }
            secret_paths = {}
            for name, value in values.items():
                path = root / name
                path.write_text(value, encoding="utf-8")
                secret_paths[name] = str(path)
            key_path = root / "ssh-key"
            key_path.write_text("private-key-fixture", encoding="utf-8")
            commands = []

            def runner(arguments, **_kwargs):
                commands.append(arguments)
                if arguments[0] == "fake-ssh-keygen":
                    return SimpleNamespace(returncode=0, stdout="")
                return SimpleNamespace(
                    returncode=0,
                    stdout="header\n1413 2026-11-17 22:06:27.438047 4000\n",
                )

            usage = policy._probe_remote_disk_usage_from_runtime(
                secret_paths,
                str(key_path),
                ssh_executable="fake-ssh",
                ssh_keygen_executable="fake-ssh-keygen",
                process_runner=runner,
            )

            self.assertEqual(usage, {"used_bytes": 4_000_000_000_000})
            ssh_call = commands[-1]
            self.assertEqual(ssh_call[-1], "app-stats show -s disk -t hour -c 1")
            self.assertIn("StrictHostKeyChecking=yes", ssh_call)
            self.assertIn("GlobalKnownHostsFile=/dev/null", ssh_call)
            self.assertNotIn("fixture", json.dumps(usage))

    def test_remote_disk_usage_metrics_file_is_private_and_contains_aggregate_values(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            metrics_path = Path(temporary_directory) / "seedbox.prom"
            policy.write_remote_disk_metrics(
                metrics_path,
                used_bytes=4_000_000_000_000,
                capacity_bytes=4_000_000_000_000,
                warning_threshold_bytes=3_000_000_000_000,
                sample_timestamp_seconds=1_700_000_000,
            )

            metrics = metrics_path.read_text(encoding="utf-8")
            self.assertEqual(metrics_path.stat().st_mode & 0o777, 0o640)
            self.assertIn("ultra_seedbox_storage_used_bytes 4000000000000", metrics)
            self.assertIn("ultra_seedbox_storage_capacity_bytes 4000000000000", metrics)
            self.assertIn("ultra_seedbox_storage_warning_threshold_bytes 3000000000000", metrics)
            self.assertIn("ultra_seedbox_storage_probe_success 1", metrics)
            self.assertIn("ultra_seedbox_storage_sample_timestamp_seconds 1700000000", metrics)
            self.assertNotIn("torrent_id", metrics)
            self.assertNotIn("/seedbox/", metrics)

    def test_remote_disk_usage_failure_writes_probe_failure_without_stale_usage(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            metrics_path = Path(temporary_directory) / "seedbox.prom"
            policy.write_remote_disk_metrics(
                metrics_path,
                used_bytes=None,
                capacity_bytes=4_000_000_000_000,
                warning_threshold_bytes=3_000_000_000_000,
                sample_timestamp_seconds=1_700_000_001,
            )

            metrics = metrics_path.read_text(encoding="utf-8")
            self.assertIn("ultra_seedbox_storage_probe_success 0", metrics)
            self.assertNotIn("ultra_seedbox_storage_used_bytes", metrics)

    def test_remote_stat_quotes_source_path_as_one_remote_argument(self):
        remote_path = "/seedbox/complete/file';touch /tmp/should-not-run;'.mkv"
        commands = []

        def runner(arguments, **_kwargs):
            commands.append(arguments[-1])
            return SimpleNamespace(
                stdout="regular file\t1024\t2023-11-14 22:13:20.123456789 +0000\n"
            )

        source_stat = policy.make_remote_source_stat(
            ["ssh", "-o", "StrictHostKeyChecking=yes"],
            "seed-user",
            "seed.example",
            process_runner=runner,
        )
        observed = source_stat(remote_path)
        command_words = __import__("shlex").split(commands[0])
        self.assertEqual(command_words[-1], remote_path)
        self.assertEqual(command_words[-2], "--")
        self.assertEqual(observed["size"], 1024)

    def test_runtime_apply_removes_seedbox_copy_after_verified_staging(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            stage_root = root / ".arr-staging"
            stage_root.mkdir()
            staged_file = stage_root / "episode.mkv"
            staged_file.write_bytes(b"payload")
            source_mtime = 1_700_000_000_000_000_000
            os.utime(staged_file, ns=(source_mtime, source_mtime))
            secret_paths = {}
            secret_values = {
                "rpc_url": "https://rpc.example.test/transmission/rpc",
                "download_root": "/seedbox/complete",
                "ssh_host": "seed.example.test",
                "ssh_username": "seed-user",
                "known_hosts": "seed.example.test ssh-ed25519 AAAA",
                "rpc_username": "rpc-user",
                "rpc_password": "rpc-password",
            }
            for name, value in secret_values.items():
                secret_file = root / name
                secret_file.write_text(value, encoding="utf-8")
                secret_paths[name] = str(secret_file)
            ssh_key = root / "ssh-key"
            ssh_key.write_text("private-key-fixture", encoding="utf-8")
            queue_root = root / "cleanup-queue"
            torrent = {
                "id": 17,
                "done_date": 1_700_000_000,
                "candidate": {
                    "complete": True,
                    "torrent_ratio": 0.5,
                    "trackers": [{"classification": "public"}],
                    "files": [{}],
                },
                "download_directory": "/seedbox/complete",
                "file_paths": ["episode.mkv"],
                "file_paths_valid": True,
                "file_sizes": [7],
                "file_sizes_valid": True,
            }
            removals = []

            class FakeTransmission:
                def __init__(self, *_args, **_kwargs):
                    pass

                def get_torrents(self):
                    return [torrent]

                def remove_torrent(self, torrent_id, *, delete_local_data):
                    removals.append((torrent_id, delete_local_data))

            receipt = staging.write_staged_torrent_receipt(
                queue_root,
                torrent["id"],
                staging.fingerprint_torrent(
                    torrent,
                    [{"remoteRoot": "/seedbox/complete", "stagingSubpath": ""}],
                ),
                staged_at_ns=source_mtime,
            )
            rpc_module = SimpleNamespace(TransmissionRPC=FakeTransmission)

            def load_module(name, _filename):
                return staging if name == "ultra_media_download_stage" else rpc_module

            def process_runner(arguments, **_kwargs):
                if arguments[0] == "fake-ssh-keygen":
                    return SimpleNamespace(returncode=0, stdout="")
                if arguments[0] == "fake-ssh":
                    return SimpleNamespace(
                        returncode=0,
                        stdout="regular file\t7\t2023-11-14 22:13:20.000000000 +0000\n",
                    )
                raise AssertionError("unexpected cleanup subprocess")

            with patch.object(policy, "_load_runtime_module", side_effect=load_module):
                report = policy.run_runtime_cleanup(
                    secret_paths,
                    str(ssh_key),
                    ssh_executable="fake-ssh",
                    ssh_keygen_executable="fake-ssh-keygen",
                    apply=True,
                    staging_root=str(stage_root),
                    queue_root=str(queue_root),
                    runtime_root=str(root / "runtime"),
                    process_runner=process_runner,
                    now_ns=1_800_000_000_000_000_000,
                )
            staged_copy_retained = staged_file.exists()

        self.assertEqual(removals, [(17, True)])
        self.assertEqual(report["removed"], 1)
        self.assertFalse(list(queue_root.glob("*.json")))
        self.assertTrue(staged_copy_retained)
        self.assertNotIn("episode.mkv", json.dumps(report))

    def test_remote_stat_parser_preserves_nanosecond_mtime(self):
        observed = policy.parse_remote_stat(
            "regular file\t1024\t2023-11-14 22:13:20.123456789 +0000\n"
        )
        self.assertEqual(
            observed,
            {
                "regular_file": True,
                "size": 1024,
                "mtime_ns": 1_700_000_000_123_456_789,
            },
        )

class CleanupExecutionTests(unittest.TestCase):
    def candidate(self):
        return {
            "torrent_id": 17,
            "done_date": 1_700_000_000,
            "complete": True,
            "torrent_ratio": 0.2,
            "runtime_config_available": True,
            "rpc_available": True,
            "trackers": [{"classification": "public"}],
            "files": [
                {
                    "mapped": True,
                    "source_mapping_verified": True,
                    "source_identity": "source-path-17",
                    "source_ownership_verified": True,
                    "source_owner_count": 1,
                    "staged_path": "/srv/media/.arr-staging/movie.mkv",
                    "expected_size": 1024,
                    "expected_mtime_ns": 1_700_000_000_000_000_000,
                }
            ],
        }

    def proof(self, _candidate):
        return policy.StagedCopyProof.verified(["/srv/media/.arr-staging/movie.mkv"])

    def staged_file(self, _file):
        return {
            "regular_file": True,
            "size": 1024,
            "mtime_ns": 1_700_000_000_000_000_000,
        }

    def test_cleanup_receipt_matching_rejects_stale_and_missing_torrents(self):
        first = {
            "id": 17,
            "download_directory": "/seedbox/complete",
            "file_paths": ["one.mkv"],
            "file_sizes": [10],
        }
        second = {
            "id": 18,
            "download_directory": "/seedbox/complete",
            "file_paths": ["two.mkv"],
            "file_sizes": [20],
        }
        receipts = [
            {"torrent_id": 17, "fingerprint": staging.fingerprint_torrent(first)},
            {"torrent_id": 18, "fingerprint": "0" * 64},
            {"torrent_id": 19, "fingerprint": "1" * 64},
        ]

        matched, counts = policy.match_staged_torrent_receipts(
            receipts,
            [first, second],
            fingerprint_fn=staging.fingerprint_torrent,
        )

        self.assertEqual([receipt["torrent_id"] for receipt in matched], [17])
        self.assertEqual(counts, {"matched": 1, "stale": 1, "missing": 1})

    def test_apply_removes_only_verified_eligible_torrent_and_its_data(self):
        removals = []
        rpc = SimpleNamespace(
            remove_torrent=lambda torrent_id, *, delete_local_data: removals.append(
                (torrent_id, delete_local_data)
            )
        )
        report = policy.execute_cleanup(
            True,
            [self.candidate()],
            staged_copy_prover=self.proof,
            staged_file_verifier=self.staged_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: True,
        )
        self.assertEqual(removals, [(17, True)])
        self.assertEqual(report["mode"], "apply")
        self.assertEqual(report["removed"], 1)
        self.assertEqual(report["eligible"], 1)

    def test_apply_revalidates_candidate_before_any_removal(self):
        removals = []
        rpc = SimpleNamespace(
            remove_torrent=lambda torrent_id, *, delete_local_data: removals.append(
                (torrent_id, delete_local_data)
            )
        )
        report = policy.execute_cleanup(
            True,
            [self.candidate()],
            staged_copy_prover=self.proof,
            staged_file_verifier=self.staged_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: False,
        )
        self.assertEqual(removals, [])
        self.assertEqual(report["removed"], 0)
        self.assertEqual(report["reasons"], {"torrent_revalidation_failed": 1})

    def test_apply_skips_busy_torrent_and_processes_other_queue_entries(self):
        events = []
        removals = []
        rpc = SimpleNamespace(
            remove_torrent=lambda torrent_id, *, delete_local_data: removals.append(
                (torrent_id, delete_local_data)
            )
        )
        first = self.candidate()
        second = self.candidate()
        second["torrent_id"] = 18
        second["files"][0]["source_identity"] = "source-path-18"
        second["files"][0]["staged_path"] = "/srv/media/.arr-staging/second.mkv"

        @contextmanager
        def candidate_lock(torrent_id):
            if torrent_id == 17:
                raise BlockingIOError("torrent is being staged")
            yield

        report = policy.execute_cleanup(
            True,
            [first, second],
            staged_copy_prover=lambda candidate: policy.StagedCopyProof.verified(
                [candidate["files"][0]["staged_path"]]
            ),
            staged_file_verifier=self.staged_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: True,
            allowed_torrent_ids={17, 18},
            candidate_lock=candidate_lock,
            on_candidate_result=lambda torrent_id, status, reasons: events.append(
                (torrent_id, status, list(reasons))
            ),
        )

        self.assertEqual(removals, [(18, True)])
        self.assertEqual(report["removed"], 1)
        self.assertIn((17, "deferred", ["torrent_operation_in_progress"]), events)

    def test_apply_runs_receipt_acknowledgement_inside_torrent_lock(self):
        events = []
        rpc = SimpleNamespace(
            remove_torrent=lambda torrent_id, *, delete_local_data: events.append(
                ("remove", torrent_id, delete_local_data)
            )
        )

        @contextmanager
        def candidate_lock(torrent_id):
            events.append(("lock_enter", torrent_id))
            yield
            events.append(("lock_exit", torrent_id))

        def on_candidate_result(torrent_id, status, _reasons):
            events.append(("receipt", torrent_id, status))

        report = policy.execute_cleanup(
            True,
            [self.candidate()],
            staged_copy_prover=self.proof,
            staged_file_verifier=self.staged_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: True,
            allowed_torrent_ids={17},
            candidate_lock=candidate_lock,
            on_candidate_result=on_candidate_result,
        )

        self.assertEqual(report["removed"], 1)
        self.assertEqual(
            events,
            [
                ("lock_enter", 17),
                ("remove", 17, True),
                ("receipt", 17, "removed"),
                ("lock_exit", 17),
            ],
        )

    def test_apply_blocks_candidates_that_share_an_imported_staged_path(self):
        removals = []
        rpc = SimpleNamespace(
            remove_torrent=lambda torrent_id, *, delete_local_data: removals.append(
                (torrent_id, delete_local_data)
            )
        )
        first = self.candidate()
        second = self.candidate()
        second["torrent_id"] = 18
        second["files"][0]["source_identity"] = "source-path-18"
        report = policy.execute_cleanup(
            True,
            [first, second],
            staged_copy_prover=self.proof,
            staged_file_verifier=self.staged_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: True,
        )
        self.assertEqual(removals, [])
        self.assertEqual(report["removed"], 0)
        self.assertEqual(report["reasons"], {"shared_file_unsafe": 2})

    def test_apply_processes_only_queued_torrent_ids_after_full_inventory_ownership_prep(self):
        removals = []
        rpc = SimpleNamespace(
            remove_torrent=lambda torrent_id, *, delete_local_data: removals.append(
                (torrent_id, delete_local_data)
            )
        )
        first = self.candidate()
        second = self.candidate()
        second["torrent_id"] = 18
        second["files"][0]["source_identity"] = "source-path-18"
        second["files"][0]["staged_path"] = "/srv/media/.arr-staging/second.mkv"

        report = policy.execute_cleanup(
            True,
            [first, second],
            staged_copy_prover=lambda candidate: policy.StagedCopyProof.verified(
                [candidate["files"][0]["staged_path"]]
            ),
            staged_file_verifier=self.staged_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: True,
            allowed_torrent_ids={18},
        )

        self.assertEqual(removals, [(18, True)])
        self.assertEqual(report["removed"], 1)

    def test_incomplete_full_inventory_blocks_cleanup_ownership_proof(self):
        removals = []
        rpc = SimpleNamespace(
            remove_torrent=lambda torrent_id, *, delete_local_data: removals.append(
                (torrent_id, delete_local_data)
            )
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging_root = str(Path(temporary_directory) / ".arr-staging")
            complete_torrent = {
                "id": 17,
                "done_date": 1_700_000_000,
                "candidate": self.candidate(),
                "download_directory": "/seedbox/complete",
                "file_paths": ["movie.mkv"],
                "file_paths_valid": True,
                "file_sizes": [1024],
                "file_sizes_valid": True,
            }
            incomplete_torrent = {
                "id": 18,
                "candidate": {"files": [{}]},
                "download_directory": "/seedbox/complete",
                "file_paths": ["unknown.mkv"],
                "file_paths_valid": False,
                "file_sizes": [1024],
                "file_sizes_valid": False,
            }
            candidates = policy.build_cleanup_candidates(
                [complete_torrent, incomplete_torrent],
                [{"remoteRoot": "/seedbox/complete", "stagingSubpath": ""}],
                staging_root=staging_root,
                path_mapper=lambda _directory, _file, _mappings, *, staging_root: (
                    f"{staging_root}/movie.mkv"
                ),
            )

        report = policy.execute_cleanup(
            True,
            candidates,
            staged_copy_prover=self.proof,
            staged_file_verifier=self.staged_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: True,
            allowed_torrent_ids={17},
        )

        self.assertEqual(removals, [])
        self.assertEqual(report["removed"], 0)
        self.assertEqual(report["reasons"], {"source_ownership_unverified": 1})

    def test_incomplete_inventory_in_unrelated_download_directory_does_not_block_candidate_ownership(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging_root = str(Path(temporary_directory) / ".arr-staging")
            valid_candidate = self.candidate()
            valid_candidate["files"][0]["source_identity"] = None
            complete_torrent = {
                "id": 17,
                "done_date": 1_700_000_000,
                "candidate": valid_candidate,
                "download_directory": "/seedbox/complete",
                "file_paths": ["movie.mkv"],
                "file_paths_valid": True,
                "file_sizes": [1024],
                "file_sizes_valid": True,
            }
            incomplete_torrent = {
                "id": 18,
                "candidate": {"complete": False, "files": [{}]},
                "download_directory": "/seedbox/incomplete",
                "file_paths": ["unknown.mkv"],
                "file_paths_valid": False,
                "file_sizes": [None],
                "file_sizes_valid": False,
            }

            candidates = policy.build_cleanup_candidates(
                [complete_torrent, incomplete_torrent],
                [
                    {"remoteRoot": "/seedbox/complete", "stagingSubpath": ""},
                    {"remoteRoot": "/seedbox/incomplete", "stagingSubpath": ""},
                ],
                staging_root=staging_root,
                path_mapper=lambda _directory, file_path, _mappings, *, staging_root: (
                    f"{staging_root}/{file_path}"
                ),
            )

        by_id = {candidate["torrent_id"]: candidate for candidate in candidates}
        self.assertTrue(by_id[17]["files"][0]["source_ownership_verified"])
        self.assertEqual(by_id[17]["files"][0]["source_owner_count"], 1)
        self.assertFalse(by_id[18]["files"][0]["source_ownership_verified"])

    def test_unknown_inventory_directory_still_blocks_all_source_ownership(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging_root = str(Path(temporary_directory) / ".arr-staging")
            complete_torrent = {
                "id": 17,
                "done_date": 1_700_000_000,
                "candidate": self.candidate(),
                "download_directory": "/seedbox/complete",
                "file_paths": ["movie.mkv"],
                "file_paths_valid": True,
                "file_sizes": [1024],
                "file_sizes_valid": True,
            }
            unknown_scope_torrent = {
                "id": 18,
                "candidate": {"complete": False, "files": [{}]},
                "download_directory": None,
                "file_paths": [],
                "file_paths_valid": False,
                "file_sizes": [],
                "file_sizes_valid": False,
            }

            candidates = policy.build_cleanup_candidates(
                [complete_torrent, unknown_scope_torrent],
                [{"remoteRoot": "/seedbox/complete", "stagingSubpath": ""}],
                staging_root=staging_root,
                path_mapper=lambda _directory, file_path, _mappings, *, staging_root: (
                    f"{staging_root}/{file_path}"
                ),
            )

        by_id = {candidate["torrent_id"]: candidate for candidate in candidates}
        self.assertFalse(by_id[17]["files"][0]["source_ownership_verified"])
        self.assertEqual(by_id[17]["files"][0]["source_owner_count"], None)

    def test_queued_torrent_remains_blocked_by_unqueued_shared_source_owner(self):
        removals = []
        rpc = SimpleNamespace(
            remove_torrent=lambda torrent_id, *, delete_local_data: removals.append(
                (torrent_id, delete_local_data)
            )
        )
        first = self.candidate()
        second = self.candidate()
        second["torrent_id"] = 18
        second["files"][0]["source_identity"] = first["files"][0]["source_identity"]
        second["files"][0]["staged_path"] = "/srv/media/.arr-staging/second.mkv"

        report = policy.execute_cleanup(
            True,
            [first, second],
            staged_copy_prover=lambda candidate: policy.StagedCopyProof.verified(
                [candidate["files"][0]["staged_path"]]
            ),
            staged_file_verifier=self.staged_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: True,
            allowed_torrent_ids={17},
        )

        self.assertEqual(removals, [])
        self.assertEqual(report["removed"], 0)
        self.assertEqual(report["reasons"], {"source_file_shared": 1})

    def test_report_only_never_calls_transmission_removal(self):
        removals = []
        rpc = SimpleNamespace(
            remove_torrent=lambda torrent_id, *, delete_local_data: removals.append(
                (torrent_id, delete_local_data)
            )
        )
        report = policy.execute_cleanup(
            True,
            [self.candidate()],
            staged_copy_prover=self.proof,
            staged_file_verifier=self.staged_file,
            transmission_rpc=rpc,
            apply=False,
        )
        self.assertEqual(removals, [])
        self.assertEqual(report["mode"], "report-only")
        self.assertEqual(report["eligible"], 1)

    def test_failed_staging_never_removes_transmission_or_source_data(self):
        removals = []
        rpc = SimpleNamespace(
            remove_torrent=lambda torrent_id, *, delete_local_data: removals.append(
                (torrent_id, delete_local_data)
            )
        )
        report = policy.execute_cleanup(
            False,
            [self.candidate()],
            staged_copy_prover=self.proof,
            staged_file_verifier=self.staged_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: True,
        )
        self.assertEqual(removals, [])
        self.assertEqual(report["removed"], 0)
        self.assertEqual(report["reasons"], {"staging_not_successful": 1})


class DownloadStagingTests(unittest.TestCase):
    def test_stage_main_passes_private_queue_root_and_emits_json_summary(self):
        captured = {}
        result = {
            "completed_candidates": 2,
            "staged": 1,
            "skipped_incomplete": 0,
            "skipped_unknown_path": 0,
            "skipped_malformed_path": 0,
            "failed": 1,
        }
        arguments = [
            "--stage-downloads",
            "--rpc-url", "/secret/rpc-url",
            "--download-root", "/secret/download-root",
            "--ssh-host", "/secret/ssh-host",
            "--ssh-username", "/secret/ssh-username",
            "--known-hosts", "/secret/known-hosts",
            "--ssh-key", "/secret/ssh-key",
            "--rpc-username", "/secret/rpc-username",
            "--rpc-password", "/secret/rpc-password",
            "--ssh", "fake-ssh",
            "--ssh-keygen", "fake-ssh-keygen",
            "--rsync", "fake-rsync",
            "--cleanup-queue-root", "/var/lib/ultra-media/cleanup-queue",
        ]

        def fake_stage(_secret_paths, _key, **kwargs):
            captured.update(kwargs)
            return result

        output = io.StringIO()
        with patch.object(staging, "_stage_from_runtime_files", side_effect=fake_stage):
            with redirect_stdout(output):
                status = staging.main(arguments)

        self.assertEqual(status, 1)
        self.assertEqual(
            captured["cleanup_queue_root"],
            "/var/lib/ultra-media/cleanup-queue",
        )
        event = json.loads(output.getvalue().splitlines()[-1])
        self.assertEqual(event["event"], "staging_run_result")
        self.assertEqual(event["staged"], 1)
        self.assertEqual(event["failed"], 1)
    def setUp(self):
        self._torrent_id = 1
        self.mappings = staging.normalize_download_root(
            "/seedbox/complete downloads"
        )

    def write_runtime_secrets(self, root, rpc_url="https://rpc.example.test/transmission/rpc"):
        values = {
            "rpc_url": rpc_url,
            "download_root": "/seedbox/complete downloads",
            "ssh_host": "seedbox.example.test",
            "ssh_username": "seed-user",
            "known_hosts": "seedbox.example.test ssh-ed25519 fake-key",
            "rpc_username": "test-user",
            "rpc_password": "test-password",
        }
        paths = {}
        for name, value in values.items():
            path = root / name
            path.write_text(value, encoding="utf-8")
            paths[name] = str(path)
        return paths

    def torrent(self, complete, download_directory, file_paths):
        torrent_id = self._torrent_id
        self._torrent_id += 1
        return {
            "id": torrent_id,
            "done_date": 1_700_000_000 + torrent_id,
            "candidate": {"complete": complete},
            "download_directory": download_directory,
            "file_paths": file_paths,
            "file_paths_valid": file_paths is not None,
            "file_sizes": [1] * len(file_paths) if file_paths is not None else [],
            "file_sizes_valid": file_paths is not None,
        }

    def test_staging_plan_counts_only_complete_mapped_files(self):
        complete = {
            "id": 17,
            "done_date": 1_700_000_000,
            "candidate": {"complete": True, "files": [{}, {}]},
            "download_directory": "/seedbox/complete downloads/Season 1",
            "file_paths": ["A/movie.mkv", "A/movie.srt"],
            "file_paths_valid": True,
            "file_sizes": [1000, 50],
            "file_sizes_valid": True,
        }
        incomplete = {
            **complete,
            "id": 18,
            "candidate": {"complete": False, "files": [{}, {}]},
        }
        unmapped = {
            **complete,
            "id": 19,
            "download_directory": "/seedbox/other",
        }

        plan = staging.build_staging_plan(
            [complete, incomplete, unmapped], self.mappings
        )

        self.assertEqual(plan["totals"], {
            "torrents": 1,
            "files": 2,
            "bytes": 1050,
            "unknown_size_files": 0,
        })
        self.assertEqual(len(plan["torrents"]), 1)
        self.assertEqual(plan["torrents"][0]["torrent_id"], 17)

    def test_staging_plan_orders_valid_completion_timestamps_oldest_first(self):
        newer = self.torrent(True, "/seedbox/complete downloads", ["newer.mkv"])
        older = self.torrent(True, "/seedbox/complete downloads", ["older.mkv"])
        same_age_first = self.torrent(True, "/seedbox/complete downloads", ["tie-first.mkv"])
        same_age_second = self.torrent(True, "/seedbox/complete downloads", ["tie-second.mkv"])
        newer["done_date"] = 1_700_000_300
        older["done_date"] = 1_700_000_100
        same_age_first["done_date"] = 1_700_000_200
        same_age_second["done_date"] = 1_700_000_200

        plan = staging.build_staging_plan(
            [newer, same_age_first, older, same_age_second], self.mappings
        )

        self.assertEqual(
            [item["torrent_id"] for item in plan["torrents"]],
            [older["id"], same_age_first["id"], same_age_second["id"], newer["id"]],
        )

    def test_staging_plan_skips_completed_torrents_without_orderable_completion_time(self):
        unknown = self.torrent(True, "/seedbox/complete downloads", ["unknown.mkv"])
        dated = self.torrent(True, "/seedbox/complete downloads", ["dated.mkv"])
        unknown["done_date"] = None
        dated["done_date"] = 1_700_000_100

        plan = staging.build_staging_plan([unknown, dated], self.mappings)

        self.assertEqual(plan["counts"]["skipped_unknown_completion_time"], 1)
        self.assertEqual([item["torrent_id"] for item in plan["torrents"]], [dated["id"]])
        self.assertEqual(plan["totals"]["torrents"], 1)

    def test_staging_plan_marks_unknown_total_bytes_for_eta(self):
        torrent = {
            "id": 20,
            "done_date": 1_700_000_000,
            "candidate": {"complete": True, "files": [{}]},
            "download_directory": "/seedbox/complete downloads/Season 1",
            "file_paths": ["movie.mkv"],
            "file_paths_valid": True,
            "file_sizes": [None],
            "file_sizes_valid": False,
        }

        plan = staging.build_staging_plan([torrent], self.mappings)

        self.assertEqual(plan["totals"]["bytes"], None)
        self.assertEqual(plan["totals"]["unknown_size_files"], 1)

    def test_progress_reporter_emits_one_minute_aggregate_eta_without_identifiers(self):
        now = [0.0]
        events = []
        reporter = staging.StageProgressReporter(
            {"torrents": 1, "files": 2, "bytes": 1000, "unknown_size_files": 0},
            emit=events.append,
            clock=lambda: now[0],
        )

        reporter.update(torrents_done=0, files_done=0, bytes_done=0, force=True)
        now[0] = 59
        reporter.update(torrents_done=0, files_done=1, bytes_done=400)
        self.assertEqual(len(events), 1)
        now[0] = 60
        reporter.update(torrents_done=0, files_done=1, bytes_done=500)

        self.assertEqual(len(events), 2)
        self.assertEqual(events[-1]["event"], "staging_progress")
        self.assertEqual(events[-1]["files_transferred"], 1)
        self.assertEqual(events[-1]["bytes_transferred"], 500)
        self.assertEqual(events[-1]["bytes_total"], 1000)
        self.assertEqual(events[-1]["percent_complete"], 50.0)
        self.assertEqual(events[-1]["eta_seconds"], 60)
        self.assertNotIn("torrent_id", events[-1])
        self.assertNotIn("path", events[-1])

    def test_progress_reporter_tracks_oldest_pending_completion_age(self):
        monotonic_now = [0.0]
        wall_now = [1_700_003_600]
        events = []
        reporter = staging.StageProgressReporter(
            {"torrents": 2, "files": 2, "bytes": 200, "unknown_size_files": 0},
            completion_times=[1_700_000_000, 1_700_001_800],
            emit=events.append,
            clock=lambda: monotonic_now[0],
            wall_clock=lambda: wall_now[0],
        )

        reporter.update(torrents_done=0, files_done=0, bytes_done=0, force=True)
        self.assertEqual(events[-1]["time_behind_seconds"], 3_600)
        self.assertEqual(events[-1]["unorderable_completed_torrents"], 0)

        monotonic_now[0] = 1
        wall_now[0] += 10
        reporter.update(
            torrents_done=1,
            files_done=1,
            bytes_done=100,
            event="torrent_staged",
            force=True,
        )
        self.assertEqual(events[-1]["time_behind_seconds"], 1_810)

        monotonic_now[0] = 2
        reporter.update(
            torrents_done=2,
            files_done=2,
            bytes_done=200,
            event="staging_completed",
            force=True,
        )
        self.assertEqual(events[-1]["time_behind_seconds"], 0)

    def test_progress_reporter_marks_lag_unknown_when_completion_times_are_missing(self):
        events = []
        reporter = staging.StageProgressReporter(
            {"torrents": 1, "files": 1, "bytes": 100, "unknown_size_files": 0},
            completion_times=[1_700_000_000],
            unorderable_completed_torrents=1,
            emit=events.append,
            clock=lambda: 0.0,
            wall_clock=lambda: 1_700_003_600,
        )

        reporter.update(torrents_done=0, files_done=0, bytes_done=0, force=True)

        self.assertIsNone(events[-1]["time_behind_seconds"])
        self.assertEqual(events[-1]["unorderable_completed_torrents"], 1)

    def test_torrent_completion_events_do_not_distort_heartbeat_rate(self):
        now = [0.0]
        events = []
        reporter = staging.StageProgressReporter(
            {"torrents": 2, "files": 2, "bytes": 1000, "unknown_size_files": 0},
            emit=events.append,
            clock=lambda: now[0],
        )
        reporter.update(torrents_done=0, files_done=0, bytes_done=0, event="staging_started", force=True)
        now[0] = 59
        reporter.update(torrents_done=1, files_done=1, bytes_done=400, event="torrent_staged", force=True)
        now[0] = 60
        reporter.update(torrents_done=1, files_done=1, bytes_done=500)

        heartbeat = events[-1]
        self.assertEqual(heartbeat["event"], "staging_progress")
        self.assertAlmostEqual(heartbeat["bytes_per_second"], 500 / 60, places=2)
        self.assertEqual(heartbeat["eta_seconds"], 60)

    def test_progress_reporter_omits_eta_when_total_or_rate_is_unknown(self):
        events = []
        reporter = staging.StageProgressReporter(
            {"torrents": 1, "files": 1, "bytes": None, "unknown_size_files": 1},
            emit=events.append,
            clock=lambda: 0.0,
        )

        reporter.update(torrents_done=0, files_done=0, bytes_done=0, force=True)

        self.assertIsNone(events[-1]["eta_seconds"])
        self.assertIsNone(events[-1]["bytes_total"])
        self.assertIsNone(events[-1]["percent_complete"])

    def test_rsync_progress_parser_extracts_bytes_without_emitting_diagnostic_text(self):
        output = b" 1,234,567  48%  12.34MB/s  0:00:01 (xfr#1, to-chk=0/1)\\r"
        self.assertEqual(staging.parse_rsync_progress_bytes(output), 1_234_567)
        self.assertIsNone(
            staging.parse_rsync_progress_bytes(
                b"rsync: [sender] file has vanished: private-media-name.mkv\\n"
            )
        )

    def test_rsync_runner_streams_only_parsed_byte_counts(self):
        progress = []
        command = [
            sys.executable,
            "-c",
            "import sys; sys.stdout.write(' 1,000 50% 1.00MB/s 0:00:01\\r 2,000 100% 1.00MB/s 0:00:00\\r'); sys.stdout.flush(); sys.stderr.write('rsync diagnostic with a private path'); sys.stderr.flush()",
        ]

        staging.run_rsync_with_progress(command, progress.append, poll_interval=0.01)

        self.assertGreaterEqual(len(progress), 2)
        self.assertEqual(
            list(dict.fromkeys(value for value in progress if value > 0)),
            [1000, 2000],
        )

    def test_rsync_runner_reports_heartbeat_when_no_progress_text_arrives(self):
        progress = []
        command = [sys.executable, "-c", "import time; time.sleep(0.15)"]

        staging.run_rsync_with_progress(
            command,
            progress.append,
            poll_interval=0.02,
        )

        self.assertGreaterEqual(len(progress), 3)
        self.assertTrue(all(value == 0 for value in progress))

    def test_staging_reports_transfer_progress_and_torrent_completion(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            staging_root = root / ".arr-staging"
            torrent = {
                "id": 27,
                "done_date": 1_700_000_000,
                "candidate": {"complete": True, "files": [{}]},
                "download_directory": "/seedbox/complete downloads/Season 1",
                "file_paths": ["episode.mkv"],
                "file_paths_valid": True,
                "file_sizes": [5],
                "file_sizes_valid": True,
            }
            events = []
            reporter = staging.StageProgressReporter(
                {"torrents": 1, "files": 1, "bytes": 5, "unknown_size_files": 0},
                emit=events.append,
                clock=lambda: 60.0,
            )

            def transfer(_remote, local_temporary, report_progress):
                Path(local_temporary).write_bytes(b"12345")
                report_progress(5)

            result = staging.stage_completed_downloads(
                [torrent], self.mappings, transfer,
                staging_root=staging_root,
                progress_reporter=reporter,
            )

            self.assertEqual(result["staged"], 1)
            self.assertEqual((staging_root / "Season 1" / "episode.mkv").read_bytes(), b"12345")
            self.assertTrue(any(event["event"] == "torrent_staged" for event in events))
            final = events[-1]
            self.assertEqual(final["torrents_published"], 1)
            self.assertEqual(final["files_transferred"], 1)
            self.assertEqual(final["bytes_transferred"], 5)
            self.assertNotIn("torrent_id", final)

    def test_torrent_fingerprint_changes_when_remote_mapping_changes(self):
        torrent = {
            "id": 23,
            "download_directory": "/seedbox/complete",
            "file_paths": ["episode.mkv"],
            "file_sizes": [10],
        }
        first_mapping = [{"remoteRoot": "/seedbox/complete", "stagingSubpath": ""}]
        changed_mapping = [{"remoteRoot": "/seedbox/complete", "stagingSubpath": "incoming"}]

        first = staging.fingerprint_torrent(torrent, first_mapping)
        second = staging.fingerprint_torrent(torrent, changed_mapping)

        self.assertNotEqual(first, second)
        self.assertNotIn("episode.mkv", first)
        self.assertEqual(len(first), 64)

    def test_staged_torrent_receipts_are_private_atomic_and_due_ordered(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            queue_root = Path(temporary_directory) / "cleanup-queue"
            fingerprint = "a" * 64
            receipt = staging.write_staged_torrent_receipt(
                queue_root, 17, fingerprint, staged_at_ns=1_000_000_000
            )
            receipt_path = Path(receipt["receipt_path"])

            self.assertTrue(receipt_path.is_file())
            self.assertEqual(receipt_path.stat().st_mode & 0o777, 0o600)
            self.assertNotEqual(receipt_path.stem, "17")
            self.assertEqual(
                staging.read_pending_torrent_receipts(queue_root, now_ns=receipt["next_attempt_ns"] - 1),
                [],
            )
            self.assertEqual(
                staging.read_pending_torrent_receipts(queue_root, now_ns=receipt["next_attempt_ns"]),
                [{key: value for key, value in receipt.items() if key != "receipt_path"}],
            )
            duplicate = staging.write_staged_torrent_receipt(
                queue_root, 17, fingerprint, staged_at_ns=2_000_000_000
            )
            self.assertEqual(len(list(queue_root.glob("*.json"))), 1)
            self.assertEqual(duplicate["staged_at_ns"], 2_000_000_000)
            self.assertNotEqual(duplicate["receipt_id"], receipt["receipt_id"])
            self.assertFalse(staging.ack_staged_torrent_receipt(queue_root, receipt))
            self.assertTrue(staging.ack_staged_torrent_receipt(queue_root, duplicate))

    def test_queue_receipt_updates_serialize_on_the_state_directory_lock(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            queue_root = Path(temporary_directory) / "cleanup-queue"
            started = threading.Event()
            finished = threading.Event()

            def write_receipt():
                started.set()
                staging.write_staged_torrent_receipt(
                    queue_root,
                    29,
                    "e" * 64,
                    staged_at_ns=1_000_000_000,
                )
                finished.set()

            with staging.cleanup_queue_lock(queue_root):
                worker = threading.Thread(target=write_receipt)
                worker.start()
                self.assertTrue(started.wait(timeout=1))
                time.sleep(0.05)
                self.assertFalse(finished.is_set())
            worker.join(timeout=2)
            self.assertFalse(worker.is_alive())
            self.assertTrue(finished.is_set())

    def test_defer_of_stale_receipt_does_not_overwrite_new_stage_generation(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            queue_root = Path(temporary_directory) / "cleanup-queue"
            fingerprint = "d" * 64
            old_receipt = staging.write_staged_torrent_receipt(
                queue_root, 28, fingerprint, staged_at_ns=1_000_000_000
            )
            new_receipt = staging.write_staged_torrent_receipt(
                queue_root, 28, fingerprint, staged_at_ns=2_000_000_000
            )

            result = staging.defer_staged_torrent_receipt(
                queue_root,
                old_receipt,
                now_ns=3_000_000_000,
                reason="staged_copy_pending",
            )

            self.assertIsNone(result)
            current = staging.read_pending_torrent_receipts(
                queue_root, now_ns=2_000_000_000
            )
            self.assertEqual(current, [{key: value for key, value in new_receipt.items() if key != "receipt_path"}])

    def test_receipt_retry_uses_bounded_backoff_and_ack_requires_matching_fingerprint(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            queue_root = Path(temporary_directory) / "cleanup-queue"
            fingerprint = "b" * 64
            receipt = staging.write_staged_torrent_receipt(
                queue_root, 18, fingerprint, staged_at_ns=1_000_000_000
            )
            first_retry = staging.defer_staged_torrent_receipt(
                queue_root, receipt, now_ns=2_000_000_000, reason="staged_copy_pending"
            )
            self.assertEqual(first_retry["next_attempt_ns"], 62_000_000_000)
            second_retry = staging.defer_staged_torrent_receipt(
                queue_root, first_retry, now_ns=63_000_000_000, reason="staged_copy_pending"
            )
            self.assertEqual(second_retry["next_attempt_ns"], 183_000_000_000)
            policy_retry = staging.defer_staged_torrent_receipt(
                queue_root, second_retry, now_ns=184_000_000_000, reason="below_retention_threshold"
            )
            self.assertEqual(policy_retry["next_attempt_ns"], 3_784_000_000_000)
            stale_receipt = {**policy_retry, "fingerprint": "c" * 64}
            self.assertFalse(staging.ack_staged_torrent_receipt(queue_root, stale_receipt))
            self.assertTrue(staging.ack_staged_torrent_receipt(queue_root, policy_retry))
            self.assertEqual(list(queue_root.glob("*.json")), [])

    def test_torrent_lock_supports_nonblocking_busy_detection(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            runtime_root = Path(temporary_directory)
            with staging.torrent_operation_lock(runtime_root, 31):
                with self.assertRaises(BlockingIOError):
                    with staging.torrent_operation_lock(runtime_root, 31, blocking=False):
                        self.fail("a nonblocking lock must not enter while held")

    def test_per_torrent_locks_serialize_same_torrent_but_allow_distinct_torrents(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            runtime_root = Path(temporary_directory)
            entered = threading.Event()
            acquired_same = threading.Event()
            acquired_other = threading.Event()
            with staging.torrent_operation_lock(runtime_root, 21):
                def acquire_same():
                    entered.set()
                    with staging.torrent_operation_lock(runtime_root, 21):
                        acquired_same.set()

                same_worker = threading.Thread(target=acquire_same)
                same_worker.start()
                self.assertTrue(entered.wait(timeout=1))
                with staging.torrent_operation_lock(runtime_root, 22):
                    acquired_other.set()
                self.assertTrue(acquired_other.is_set())
                self.assertFalse(acquired_same.is_set())
            same_worker.join(timeout=2)
            self.assertFalse(same_worker.is_alive())
            self.assertTrue(acquired_same.is_set())

    def test_ssh_port_defaults_to_22_without_a_secret_file(self):
        self.assertEqual(staging.normalize_ssh_port(), 22)
        self.assertEqual(staging.normalize_ssh_port(None), 22)
        self.assertEqual(staging.normalize_ssh_port("2222"), 2222)
        with self.assertRaises(staging.StagingConfigurationError):
            staging.normalize_ssh_port("not-a-port")

    def test_invalid_rpc_port_is_rejected_before_any_connection(self):
        with self.assertRaises(staging.StagingConfigurationError):
            staging.validate_staging_config(
                "https://127.0.0.1:99999/transmission/rpc",
                "/seedbox/complete downloads",
                "test-user",
                "test-password",
            )

    def test_missing_scalar_secret_blocks_before_ssh_or_rpc(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            key_path = root / "ssh-key"
            key_path.write_text("test key", encoding="utf-8")
            secret_paths = self.write_runtime_secrets(root)
            secret_paths.pop("ssh_host")
            process_calls = []

            def mocked_process_runner(*args, **_kwargs):
                process_calls.append(args)
                return SimpleNamespace(returncode=0)

            old_adapter = sys.modules.get("transmission_rpc")
            sys.modules["transmission_rpc"] = transmission_rpc
            try:
                with patch.object(transmission_rpc, "build_opener") as build_opener:
                    with self.assertRaises(staging.StagingConfigurationError) as raised:
                        staging._stage_from_runtime_files(
                            secret_paths,
                            str(key_path),
                            ssh_executable="fake-ssh",
                            ssh_keygen_executable="fake-ssh-keygen",
                            rsync_executable="fake-rsync",
                            process_runner=mocked_process_runner,
                            staging_root=root / ".arr-staging",
                        )
                self.assertEqual(raised.exception.reason, "credential_unavailable")
                self.assertEqual(process_calls, [])
                build_opener.assert_not_called()
            finally:
                if old_adapter is None:
                    sys.modules.pop("transmission_rpc", None)
                else:
                    sys.modules["transmission_rpc"] = old_adapter

    def test_http_rpc_url_is_rejected_before_any_network_request(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            key_path = root / "ssh-key"
            key_path.write_text("test key", encoding="utf-8")
            secret_paths = self.write_runtime_secrets(
                root, "http://rpc.example.test/transmission/rpc"
            )
            process_calls = []

            def mocked_process_runner(*args, **_kwargs):
                process_calls.append(args)
                return SimpleNamespace(returncode=0)

            old_adapter = sys.modules.get("transmission_rpc")
            sys.modules["transmission_rpc"] = transmission_rpc
            try:
                with patch.object(transmission_rpc, "build_opener") as build_opener:
                    with self.assertRaises(staging.StagingConfigurationError) as raised:
                        staging._stage_from_runtime_files(
                            secret_paths,
                            str(key_path),
                            ssh_executable="fake-ssh",
                            ssh_keygen_executable="fake-ssh-keygen",
                            rsync_executable="fake-rsync",
                            process_runner=mocked_process_runner,
                            staging_root=root / ".arr-staging",
                        )
                self.assertEqual(raised.exception.reason, "rpc_url_insecure")
                self.assertEqual(process_calls, [])
                build_opener.assert_not_called()
            finally:
                if old_adapter is None:
                    sys.modules.pop("transmission_rpc", None)
                else:
                    sys.modules["transmission_rpc"] = old_adapter

    def test_malformed_rpc_hostname_is_rejected_before_connection(self):
        with self.assertRaises(staging.StagingConfigurationError):
            staging.validate_staging_config(
                "https://%zz/transmission/rpc",
                "/seedbox/complete downloads",
                "test-user",
                "test-password",
            )

    def test_rpc_url_with_raw_whitespace_is_rejected(self):
        with self.assertRaises(staging.StagingConfigurationError):
            staging.validate_staging_config(
                "https://127.0.0.1/transmission rpc",
                "/seedbox/complete downloads",
                "test-user",
                "test-password",
            )

    def test_mapping_normalizes_whitespace_and_nested_remote_paths(self):
        self.assertEqual(
            self.mappings,
            [
                {
                    "remoteRoot": "/seedbox/complete downloads",
                    "stagingSubpath": "",
                }
            ],
        )
        self.assertEqual(
            staging.map_remote_path_to_staging(
                "/seedbox/complete downloads",
                "A Series/Season 1/episode 01.mkv",
                self.mappings,
            ),
            "/srv/media/.arr-staging/A Series/Season 1/episode 01.mkv",
        )

    def test_traversal_paths_are_rejected(self):
        with self.assertRaises(staging.StagingConfigurationError):
            staging.normalize_download_root("/")
        with self.assertRaises(staging.StagingConfigurationError):
            staging.normalize_download_root("/seedbox/../outside")
        with self.assertRaises(staging.StagingConfigurationError):
            staging.map_remote_path_to_staging(
                "/seedbox/complete downloads",
                "../outside.mkv",
                self.mappings,
            )

    def test_source_mapping_provenance_requires_one_valid_rpc_mapping_match(self):
        valid_torrent = self.torrent(
            True,
            "/seedbox/complete downloads",
            ["Series/episode.mkv"],
        )
        normalized = staging.normalize_transmission_source_mappings(
            valid_torrent, self.mappings
        )
        self.assertEqual(
            normalized["files"],
            [
                {
                    "mapped": True,
                    "source_mapping_verified": True,
                    "source_identity": None,
                    "source_ownership_verified": False,
                    "source_owner_count": None,
                    "local_match": False,
                    "shared_safe": False,
                }
            ],
        )
        self.assertNotIn("episode.mkv", repr(normalized))

        ambiguous_mappings = [
            {"remoteRoot": "/seedbox/complete downloads", "stagingSubpath": ""},
            {
                "remoteRoot": "/seedbox/complete downloads/Series",
                "stagingSubpath": "series",
            },
        ]
        missing_file_path = self.torrent(
            True, "/seedbox/complete downloads", None
        )
        missing_file_path["candidate"]["files"] = [
            {"mapped": False, "local_match": False, "shared_safe": False}
        ]
        missing_file_path["file_paths_valid"] = False
        invalid_cases = (
            self.torrent(True, "", ["Series/episode.mkv"]),
            missing_file_path,
            self.torrent(True, "/seedbox/complete downloads", ["Series/episode.mkv"]),
            self.torrent(True, "/seedbox/other", ["Series/episode.mkv"]),
            self.torrent(True, "/seedbox/complete downloads", ["../episode.mkv"]),
            self.torrent(True, "/seedbox/complete downloads", ["Series/episode.mkv"]),
        )
        case_mappings = (
            self.mappings,
            self.mappings,
            [],
            self.mappings,
            self.mappings,
            ambiguous_mappings,
        )
        for torrent, mappings in zip(invalid_cases, case_mappings):
            with self.subTest(torrent=torrent):
                normalized = staging.normalize_transmission_source_mappings(
                    torrent, mappings
                )
                file_records = normalized["files"]
                self.assertTrue(file_records)
                self.assertTrue(
                    all(
                        record["source_mapping_verified"] is False
                        and record["mapped"] is False
                        for record in file_records
                    )
                )

    def test_only_complete_torrents_with_known_safe_paths_are_staged(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / ".arr-staging"
            transfers = []

            def transfer(remote_source, temporary_file, report_progress):
                transfers.append(remote_source)
                temporary_file.write_bytes(b"complete payload")
                report_progress(len(b"complete payload"))

            result = staging.stage_completed_downloads(
                [
                    self.torrent(
                        True,
                        "/seedbox/complete downloads",
                        ["A Series/Season 1/episode 01.mkv"],
                    ),
                    self.torrent(
                        False,
                        "/seedbox/complete downloads",
                        ["incomplete.mkv"],
                    ),
                    self.torrent(True, "/seedbox/other", ["unknown.mkv"]),
                    self.torrent(
                        True,
                        "/seedbox/complete downloads",
                        ["../outside.mkv"],
                    ),
                ],
                self.mappings,
                transfer,
                staging_root=root,
            )
            destination = (
                root / "A Series" / "Season 1" / "episode 01.mkv"
            )
            self.assertEqual(destination.read_bytes(), b"complete payload")
            self.assertEqual(
                transfers,
                [
                    "/seedbox/complete downloads/A Series/Season 1/episode 01.mkv"
                ],
            )
            self.assertEqual(
                result,
                {
                    "completed_candidates": 3,
                    "staged": 1,
                    "reused_files": 0,
                    "torrents_total": 1,
                    "files_total": 1,
                    "bytes_total": 1,
                    "files_transferred": 1,
                    "bytes_transferred": 16,
                    "files_reused": 0,
                    "bytes_reused": 0,
                    "receipts_created": 0,
                    "skipped_incomplete": 1,
                    "skipped_unknown_path": 1,
                    "skipped_malformed_path": 1,
                    "skipped_unknown_completion_time": 0,
                    "failed": 0,
                },
            )

    def test_stage_receipt_callback_runs_only_after_all_torrent_files_are_published(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / ".arr-staging"
            torrent = self.torrent(
                True,
                "/seedbox/complete downloads/Season 1",
                ["one.mkv", "two.mkv"],
            )
            published_callbacks = []

            def transfer(_remote_source, temporary_file, report_progress):
                temporary_file.write_bytes(b"payload")
                report_progress(7)

            def on_torrent_staged(staged_torrent):
                self.assertTrue((root / "Season 1" / "one.mkv").is_file())
                self.assertTrue((root / "Season 1" / "two.mkv").is_file())
                published_callbacks.append(staged_torrent["id"])

            result = staging.stage_completed_downloads(
                [torrent],
                self.mappings,
                transfer,
                staging_root=root,
                on_torrent_staged=on_torrent_staged,
            )

            self.assertEqual(result["staged"], 1)
            self.assertEqual(published_callbacks, [torrent["id"]])

    def test_successful_torrent_receipt_survives_later_torrent_failure(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            staging_root = root / ".arr-staging"
            queue_root = root / "cleanup-queue"
            runtime_root = root / "runtime"
            first = self.torrent(True, "/seedbox/complete downloads", ["first.mkv"])
            second = self.torrent(True, "/seedbox/complete downloads", ["second.mkv"])

            def transfer(remote_source, local_temporary, report_progress):
                if remote_source.endswith("second.mkv"):
                    raise OSError("synthetic later transfer failure")
                payload = b"first payload"
                local_temporary.write_bytes(payload)
                report_progress(len(payload))

            def enqueue(torrent):
                staging.write_staged_torrent_receipt(
                    queue_root,
                    torrent["id"],
                    staging.fingerprint_torrent(torrent, self.mappings),
                    staged_at_ns=1_700_000_000_000_000_000,
                )

            result = staging.stage_completed_downloads(
                [first, second],
                self.mappings,
                transfer,
                staging_root=staging_root,
                runtime_root=runtime_root,
                on_torrent_staged=enqueue,
            )

            self.assertEqual(result["staged"], 1)
            self.assertEqual(result["failed"], 1)
            queued = staging.read_pending_torrent_receipts(
                queue_root, now_ns=1_700_000_000_000_000_000
            )
            self.assertEqual([receipt["torrent_id"] for receipt in queued], [first["id"]])
            self.assertTrue((staging_root / "first.mkv").is_file())
            self.assertFalse((staging_root / "second.mkv").exists())

    def test_stage_start_removes_only_legacy_temporary_workspaces(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging_root = Path(temporary_directory) / ".arr-staging"
            staging_root.mkdir()
            legacy = staging_root / ".incoming-old"
            legacy.mkdir()
            (legacy / "partial").write_bytes(b"old partial")
            resumable = staging_root / ".incoming-v1-current"
            resumable.mkdir()
            (staging_root / "published.mkv").write_bytes(b"published")

            result = staging.stage_completed_downloads(
                [], self.mappings, lambda *_args: self.fail("unexpected transfer"),
                staging_root=staging_root,
            )

            self.assertEqual(result["staged"], 0)
            self.assertFalse(legacy.exists())
            self.assertTrue(resumable.is_dir())
            self.assertEqual((staging_root / "published.mkv").read_bytes(), b"published")

    def test_staged_file_reuse_requires_regular_file_and_remote_size_mtime_match(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "episode.mkv"
            path.write_bytes(b"local")
            expected_mtime = 1_700_000_000_000_000_000
            os.utime(path, ns=(expected_mtime, expected_mtime))
            source_stat = lambda _remote: {
                "regular_file": True,
                "size": 5,
                "mtime_ns": expected_mtime,
            }

            self.assertTrue(
                staging.staged_file_matches_source(
                    "/seedbox/episode.mkv", path, 5, source_stat
                )
            )
            self.assertFalse(
                staging.staged_file_matches_source(
                    "/seedbox/episode.mkv",
                    path,
                    5,
                    lambda _remote: {"regular_file": True, "size": 5, "mtime_ns": expected_mtime + 1},
                )
            )
            self.assertFalse(
                staging.staged_file_matches_source(
                    "/seedbox/episode.mkv",
                    path,
                    6,
                    source_stat,
                )
            )

    def test_existing_staged_payload_is_reused_only_after_remote_size_mtime_match(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / ".arr-staging"
            destination = root / "Season 1" / "episode.mkv"
            destination.parent.mkdir(parents=True)
            destination.write_bytes(b"local")
            expected_mtime = 1_700_000_000_000_000_000
            os.utime(destination, ns=(expected_mtime, expected_mtime))
            torrent = self.torrent(
                True,
                "/seedbox/complete downloads/Season 1",
                ["episode.mkv"],
            )
            torrent["file_sizes"] = [5]
            remote_stats = []
            receipts = []

            def matching_source_stat(remote_path):
                remote_stats.append(remote_path)
                return {"regular_file": True, "size": 5, "mtime_ns": expected_mtime}

            def unexpected_transfer(*_args):
                self.fail("matching staged payload should be reused")

            result = staging.stage_completed_downloads(
                [torrent],
                self.mappings,
                unexpected_transfer,
                staging_root=root,
                source_stat=matching_source_stat,
                on_torrent_staged=receipts.append,
            )

            self.assertEqual(result["staged"], 1)
            self.assertEqual(result["reused_files"], 1)
            self.assertEqual(remote_stats, ["/seedbox/complete downloads/Season 1/episode.mkv"])
            self.assertEqual(receipts, [torrent])
            self.assertEqual(destination.read_bytes(), b"local")

    def test_staged_file_reuse_rejects_symlinked_parent_outside_staging_root(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / ".arr-staging"
            outside = Path(temporary_directory) / "outside"
            root.mkdir()
            outside.mkdir()
            destination = outside / "episode.mkv"
            destination.write_bytes(b"local")
            expected_mtime = 1_700_000_000_000_000_000
            os.utime(destination, ns=(expected_mtime, expected_mtime))
            (root / "Season 1").symlink_to(outside, target_is_directory=True)
            torrent = self.torrent(
                True,
                "/seedbox/complete downloads/Season 1",
                ["episode.mkv"],
            )
            torrent["file_sizes"] = [5]
            transfer_calls = []

            result = staging.stage_completed_downloads(
                [torrent],
                self.mappings,
                lambda *args: transfer_calls.append(args),
                staging_root=root,
                source_stat=lambda _remote: {
                    "regular_file": True,
                    "size": 5,
                    "mtime_ns": expected_mtime,
                },
            )

            self.assertEqual(result["failed"], 1)
            self.assertEqual(result["staged"], 0)
            self.assertEqual(transfer_calls, [])
            self.assertEqual(destination.read_bytes(), b"local")

    def test_stage_retry_reuses_only_a_matching_torrent_partial_workspace(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            staging_root = root / ".arr-staging"
            torrent = self.torrent(
                True,
                "/seedbox/complete downloads/Season 1",
                ["resume.mkv"],
            )
            first_workspaces = []
            partial_data = b"recoverable partial bytes"

            def interrupted_transfer(_remote, local_temporary, _report_progress):
                workdir = Path(local_temporary).parent
                first_workspaces.append(workdir)
                partial = workdir / ".rsync-partial" / Path(local_temporary).name
                partial.parent.mkdir(parents=True, exist_ok=True)
                partial.write_bytes(partial_data)
                raise OSError("synthetic interrupted rsync")

            first_result = staging.stage_completed_downloads(
                [torrent], self.mappings, interrupted_transfer, staging_root=staging_root
            )
            self.assertEqual(first_result["failed"], 1)
            self.assertTrue(first_workspaces[0].is_dir())

            observed_resume = []

            def resumed_transfer(_remote, local_temporary, report_progress):
                workdir = Path(local_temporary).parent
                observed_resume.append(
                    (workdir, (workdir / ".rsync-partial" / Path(local_temporary).name).read_bytes())
                )
                payload = b"complete resumed payload"
                Path(local_temporary).write_bytes(payload)
                report_progress(len(payload))

            second_result = staging.stage_completed_downloads(
                [torrent], self.mappings, resumed_transfer, staging_root=staging_root
            )

            self.assertEqual(second_result["staged"], 1)
            self.assertEqual(observed_resume, [(first_workspaces[0], partial_data)])
            self.assertEqual(
                (staging_root / "Season 1" / "resume.mkv").read_bytes(),
                b"complete resumed payload",
            )
            self.assertFalse(first_workspaces[0].exists())

    def test_partial_transfer_is_not_published_or_counted_complete(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / ".arr-staging"

            def partial_transfer(_remote_source, temporary_file, report_progress):
                temporary_file.write_bytes(b"partial")
                report_progress(len(b"partial"))
                raise OSError("synthetic transfer failure")

            staged_receipts = []
            result = staging.stage_completed_downloads(
                [
                    self.torrent(
                        True,
                        "/seedbox/complete downloads",
                        ["A Series/Season 1/episode 01.mkv"],
                    )
                ],
                self.mappings,
                partial_transfer,
                staging_root=root,
                on_torrent_staged=staged_receipts.append,
            )
            self.assertEqual(staged_receipts, [])
            self.assertEqual(result["staged"], 0)
            self.assertEqual(result["failed"], 1)
            self.assertFalse(
                (root / "A Series" / "Season 1" / "episode 01.mkv").exists()
            )

    def test_rsync_arguments_are_copy_only_and_protect_whitespace_paths(self):
        arguments = staging.build_rsync_arguments(
            "/nix/store/rsync/bin/rsync",
            "ssh -i /run/secrets/key",
            "seed-user@seedbox:/seedbox/complete downloads/A Series/episode 01.mkv",
            "/srv/media/.arr-staging/shows/A Series/episode 01.mkv",
        )
        self.assertIn("--protect-args", arguments)
        self.assertNotIn("--delete", arguments)
        self.assertNotIn("--remove-source-files", arguments)
        self.assertTrue(arguments[-2].endswith("episode 01.mkv"))

    def test_fake_rpc_and_mocked_rsync_stage_payload_without_live_services(self):
        server = FakeTransmissionRPCServer()
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            key_path = root / "ssh-key"
            staging_root = root / ".arr-staging"
            queue_root = root / "cleanup-queue"
            runtime_root = root / "runtime"
            key_path.write_text("test key", encoding="utf-8")
            secret_paths = self.write_runtime_secrets(root, server.url)
            Path(secret_paths["download_root"]).write_text(
                "/seedbox/complete", encoding="utf-8"
            )
            transfer_commands = []

            def mocked_process_runner(arguments, **_kwargs):
                if arguments[0] == "fake-ssh-keygen":
                    return SimpleNamespace(returncode=0)
                self.fail("staging invoked an unexpected local process")

            def mocked_progress_runner(arguments, report_progress):
                if arguments[0] != "fake-rsync":
                    self.fail("staging invoked an unexpected transfer process")
                transfer_commands.append(arguments)
                payload = b"local fixture payload"
                Path(arguments[-1]).write_bytes(payload)
                report_progress(len(payload))

            old_adapter = sys.modules.get("transmission_rpc")
            sys.modules["transmission_rpc"] = transmission_rpc
            try:
                with patch.object(
                    transmission_rpc,
                    "build_opener",
                    side_effect=lambda *_args, **_kwargs: server,
                ):
                    result = staging._stage_from_runtime_files(
                        secret_paths,
                        str(key_path),
                        ssh_executable="fake-ssh",
                        ssh_keygen_executable="fake-ssh-keygen",
                        rsync_executable="fake-rsync",
                        process_runner=mocked_process_runner,
                        progress_runner=mocked_progress_runner,
                        staging_root=staging_root,
                        runtime_root=runtime_root,
                        cleanup_queue_root=queue_root,
                    )
            finally:
                if old_adapter is None:
                    sys.modules.pop("transmission_rpc", None)
                else:
                    sys.modules["transmission_rpc"] = old_adapter
                server.close()

            self.assertEqual(result["staged"], 1)
            self.assertEqual(result["files_transferred"], 1)
            self.assertEqual(result["bytes_transferred"], 21)
            self.assertEqual(result["files_reused"], 0)
            self.assertEqual(result["bytes_reused"], 0)
            queued = staging.read_pending_torrent_receipts(
                queue_root, now_ns=time.time_ns()
            )
            self.assertEqual([receipt["torrent_id"] for receipt in queued], [17])
            self.assertEqual(len(transfer_commands), 1)
            self.assertIn("--protect-args", transfer_commands[0])
            self.assertEqual(
                (
                    staging_root
                    / "Season 1"
                    / "episode 01.mkv"
                ).read_bytes(),
                b"local fixture payload",
            )

    def test_missing_optional_runtime_members_fail_closed(self):
        with self.assertRaises(staging.StagingConfigurationError):
            staging.validate_staging_config(
                "", "/seedbox/complete downloads", "test-user", "test-password"
            )
        with self.assertRaises(staging.StagingConfigurationError):
            staging.validate_staging_config(
                "https://127.0.0.1:9091/transmission/rpc",
                "",
                "test-user",
                "test-password",
            )


class CleanupOrchestrationTests(unittest.TestCase):
    def setUp(self):
        self._source_counter = 0

    def candidate(self, **overrides):
        self._source_counter += 1
        value = {
            "complete": True,
            "done_date": 1_700_000_000,
            "torrent_ratio": 3.0,
            "runtime_config_available": True,
            "rpc_available": True,
            "trackers": [{"classification": "public"}],
            "files": [
                {
                    "mapped": True,
                    "source_mapping_verified": True,
                    "source_identity": f"fixture-source-{self._source_counter}",
                    "source_ownership_verified": True,
                    "source_owner_count": 1,
                    "staged_path": "/srv/media/.arr-staging/movie.mkv",
                    "expected_size": 1024,
                    "expected_mtime_ns": 1_700_000_000_000_000_000,
                }
            ],
        }
        value.update(overrides)
        return value

    def verified_staged_copy(self, *paths):
        return policy.StagedCopyProof.verified(paths)

    def matching_staged_file(self, _file):
        return {
            "regular_file": True,
            "size": 1024,
            "mtime_ns": 1_700_000_000_000_000_000,
        }

    def test_cleanup_skips_stage_proofs_below_retention_limits(self):
        calls = []
        now_seconds = int(time.time())
        candidate = self.candidate(
            done_date=now_seconds - (240 * 60 * 60) + 1,
            torrent_ratio=2.99,
        )
        with patch.object(policy.time, "time", return_value=now_seconds):
            report = policy.build_cleanup_report(
                True,
                [candidate],
                staged_copy_prover=lambda _candidate: calls.append("stage-proof"),
                staged_file_verifier=lambda _file: calls.append("staged-file-proof"),
            )
        self.assertEqual(calls, [])
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"below_retention_threshold": 1})

    def test_cleanup_verifies_only_after_successful_staging_and_copy_proof(self):
        events = ["stage-succeeded"]
        candidate = self.candidate()

        def prove_import(_candidate):
            events.append("staged-copy-proof")
            return self.verified_staged_copy("/srv/media/.arr-staging/movie.mkv")

        def verify_file(file_record):
            events.append("staged-copy-revalidation")
            return self.matching_staged_file(file_record)

        report = policy.build_cleanup_report(
            True,
            [candidate],
            staged_copy_prover=prove_import,
            staged_file_verifier=verify_file,
        )

        self.assertEqual(
            events,
            ["stage-succeeded", "staged-copy-proof", "staged-copy-revalidation"],
        )
        self.assertEqual(report["mode"], "report-only")
        self.assertEqual(report["eligible"], 1)

    def test_failed_staging_prevents_copy_verification(self):
        calls = []
        report = policy.build_cleanup_report(
            False,
            [self.candidate()],
            staged_copy_prover=lambda _candidate: calls.append("stage-proof"),
            staged_file_verifier=lambda _file: calls.append("staged-file-proof"),
        )
        self.assertEqual(calls, [])
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"staging_not_successful": 1})

    def test_missing_runtime_config_blocks_before_copy_verification(self):
        calls = []
        candidate = self.candidate(runtime_config_available=False)
        report = policy.build_cleanup_report(
            True,
            [candidate],
            staged_copy_prover=lambda _candidate: calls.append("stage-proof"),
            staged_file_verifier=lambda _file: calls.append("staged-file-proof"),
        )
        self.assertEqual(calls, [])
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"runtime_configuration_unavailable": 1})

    def test_unavailable_transmission_state_fails_closed(self):
        missing_rpc = self.candidate()
        missing_rpc.pop("rpc_available")
        for status in (
            {"rpc_available": False},
            {"candidate": missing_rpc},
        ):
            status_name = "transmission_state_unavailable"
            with self.subTest(status=status):
                calls = []
                candidate = status.pop("candidate") if "candidate" in status else self.candidate(**status)
                report = policy.build_cleanup_report(
                    True,
                    [candidate],
                    staged_copy_prover=lambda _candidate: calls.append("stage-proof"),
                    staged_file_verifier=lambda _file: calls.append("staged-file-proof"),
                )
                self.assertEqual(calls, [])
                self.assertEqual(report["eligible"], 0)
                self.assertEqual(report["reasons"], {status_name: 1})

    def test_cleanup_report_blocks_missing_source_mapping_provenance_before_proofs(self):
        for provenance in (None, False):
            with self.subTest(provenance=provenance):
                candidate = self.candidate()
                if provenance is None:
                    candidate["files"][0].pop("source_mapping_verified")
                else:
                    candidate["files"][0]["source_mapping_verified"] = provenance
                calls = []
                report = policy.build_cleanup_report(
                    True,
                    [candidate],
                    staged_copy_prover=lambda _candidate: calls.append("stage-proof"),
                    staged_file_verifier=lambda _file: calls.append("staged-file-proof"),
                )
                self.assertEqual(calls, [])
                self.assertEqual(report["eligible"], 0)
                self.assertEqual(report["reasons"], {"source_mapping_unverified": 1})

    def test_cleanup_report_blocks_unverified_source_ownership_before_proofs(self):
        candidate = self.candidate()
        candidate["files"][0]["source_ownership_verified"] = False
        calls = []
        report = policy.build_cleanup_report(
            True,
            [candidate],
            staged_copy_prover=lambda _candidate: calls.append("stage-proof"),
            staged_file_verifier=lambda _file: calls.append("staged-file-proof"),
        )
        self.assertEqual(calls, [])
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"source_ownership_unverified": 1})

    def test_staged_copy_proof_is_required_and_unverified_fails_closed(self):
        report = policy.build_cleanup_report(
            True,
            [self.candidate()],
            staged_copy_prover=lambda _candidate: policy.StagedCopyProof.unverified(),
            staged_file_verifier=self.matching_staged_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"staged_copy_unverified": 1})

    def test_staged_copy_proof_must_cover_every_payload_file(self):
        report = policy.build_cleanup_report(
            True,
            [self.candidate()],
            staged_copy_prover=lambda _candidate: self.verified_staged_copy(
                "/srv/media/.arr-staging/another-file.mkv"
            ),
            staged_file_verifier=self.matching_staged_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"staged_copy_unverified": 1})

    def test_staged_file_revalidation_requires_exact_size_and_mtime(self):
        mismatched_size = policy.build_cleanup_report(
            True,
            [self.candidate()],
            staged_copy_prover=lambda _candidate: self.verified_staged_copy(
                "/srv/media/.arr-staging/movie.mkv"
            ),
            staged_file_verifier=lambda _file: {
                "regular_file": True,
                "size": 1023,
                "mtime_ns": 1_700_000_000_000_000_000,
            },
        )
        self.assertEqual(mismatched_size["eligible"], 0)
        self.assertEqual(mismatched_size["reasons"], {"local_file_mismatch": 1})

        changed_stage_mtime = policy.build_cleanup_report(
            True,
            [self.candidate()],
            staged_copy_prover=lambda _candidate: self.verified_staged_copy(
                "/srv/media/.arr-staging/movie.mkv"
            ),
            staged_file_verifier=lambda _file: {
                "regular_file": True,
                "size": 1024,
                "mtime_ns": 1_700_000_000_000_000_001,
            },
        )
        self.assertEqual(changed_stage_mtime["eligible"], 0)
        self.assertEqual(changed_stage_mtime["reasons"], {"local_file_mismatch": 1})

    def test_unknown_private_account_ratio_blocks_cleanup_report(self):
        candidate = self.candidate(
            trackers=[
                {
                    "classification": "private",
                    "ratio_source_available": False,
                }
            ]
        )
        report = policy.build_cleanup_report(
            True,
            [candidate],
            staged_copy_prover=lambda _candidate: self.verified_staged_copy(
                "/srv/media/.arr-staging/movie.mkv"
            ),
            staged_file_verifier=self.matching_staged_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"private_ratio_unavailable": 1})

    def test_private_account_ratio_floor_is_applied_to_cleanup_report(self):
        candidate = self.candidate(
            trackers=[
                {
                    "classification": "private",
                    "ratio_source_available": True,
                    "account_ratio": 0.59,
                }
            ]
        )
        report = policy.build_cleanup_report(
            True,
            [candidate],
            staged_copy_prover=lambda _candidate: self.verified_staged_copy(
                "/srv/media/.arr-staging/movie.mkv"
            ),
            staged_file_verifier=self.matching_staged_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"private_ratio_below_floor": 1})

    def test_unknown_tracker_blocks_cleanup_report(self):
        candidate = self.candidate(trackers=[{"classification": "unknown"}])
        report = policy.build_cleanup_report(
            True,
            [candidate],
            staged_copy_prover=lambda _candidate: self.verified_staged_copy(
                "/srv/media/.arr-staging/movie.mkv"
            ),
            staged_file_verifier=self.matching_staged_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"tracker_classification_unknown": 1})

    def test_overlapping_staged_paths_block_every_candidate_sharing_the_path(self):
        first = self.candidate()
        second = self.candidate()
        report = policy.build_cleanup_report(
            True,
            [first, second],
            staged_copy_prover=lambda _candidate: self.verified_staged_copy(
                "/srv/media/.arr-staging/movie.mkv"
            ),
            staged_file_verifier=self.matching_staged_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"shared_file_unsafe": 2})

    def test_different_staged_paths_sharing_one_source_inode_block_cleanup(self):
        first = self.candidate()
        second = self.candidate()
        first["files"][0]["staged_path"] = "/srv/media/.arr-staging/first.mkv"
        second["files"][0]["staged_path"] = "/srv/media/.arr-staging/renamed-copy.mkv"
        for candidate in (first, second):
            candidate["files"][0]["source_identity"] = "fixture-same-inode"
            candidate["files"][0]["source_owner_count"] = 2
        report = policy.build_cleanup_report(
            True,
            [first, second],
            staged_copy_prover=lambda _candidate: self.verified_staged_copy(
                "/srv/media/.arr-staging/first.mkv", "/srv/media/.arr-staging/renamed-copy.mkv"
            ),
            staged_file_verifier=self.matching_staged_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"source_file_shared": 2})

    def test_stage_and_cleanup_lock_different_torrents_independently(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            runtime_root = Path(temporary_directory)
            acquired = threading.Event()
            with staging.torrent_operation_lock(runtime_root, 41):
                def cleanup_other_torrent():
                    with staging.torrent_operation_lock(runtime_root, 42):
                        acquired.set()

                worker = threading.Thread(target=cleanup_other_torrent)
                worker.start()
                self.assertTrue(acquired.wait(timeout=1))
                worker.join(timeout=2)
                self.assertFalse(worker.is_alive())

    def test_legacy_inventory_counts_torrent_only_and_legacy_only_records(self):
        records = [
            {
                "transmission_owned": True,
                "arr_library_owned": False,
                "path_key": "private-torrent-path",
                "inode_key": "private-torrent-inode",
            },
            {
                "transmission_owned": False,
                "arr_library_owned": True,
                "path_key": "private-legacy-path",
                "inode_key": "private-legacy-inode",
            },
        ]

        report = policy.build_legacy_library_inventory_report(records)

        self.assertEqual(
            report["counts"],
            {
                "transmission_only": 1,
                "legacy_arr_only": 1,
                "shared_path_or_inode": 0,
                "unknown_ownership": 0,
            },
        )
        self.assertEqual(
            report["reasons"],
            {"legacy_arr_only": 1, "transmission_only": 1},
        )
        self.assertEqual(report["deletable"], 0)

    def test_legacy_inventory_marks_path_and_inode_overlaps_shared(self):
        records = [
            {
                "transmission_owned": True,
                "arr_library_owned": False,
                "path_key": "private-path-overlap",
                "inode_key": "torrent-inode",
            },
            {
                "transmission_owned": False,
                "arr_library_owned": True,
                "path_key": "private-path-overlap",
                "inode_key": "legacy-inode",
            },
            {
                "transmission_owned": True,
                "arr_library_owned": False,
                "path_key": "torrent-path",
                "inode_key": "private-inode-overlap",
            },
            {
                "transmission_owned": False,
                "arr_library_owned": True,
                "path_key": "legacy-path",
                "inode_key": "private-inode-overlap",
            },
        ]

        report = policy.build_legacy_library_inventory_report(records)

        self.assertEqual(
            report["counts"],
            {
                "transmission_only": 0,
                "legacy_arr_only": 0,
                "shared_path_or_inode": 4,
                "unknown_ownership": 0,
            },
        )
        self.assertEqual(report["reasons"], {"shared_path_or_inode": 4})
        self.assertEqual(report["deletable"], 0)

    def test_legacy_inventory_missing_ownership_is_unknown_and_output_is_redacted(self):
        sensitive_values = (
            "private-torrent-name",
            "/private/media/library/episode.mkv",
            "private-inode-12345",
            "private-tracker-id-6789",
        )
        records = [
            {
                "transmission_owned": True,
                "arr_library_owned": None,
                "path_key": sensitive_values[1],
                "inode_key": sensitive_values[2],
                "torrent_name": sensitive_values[0],
                "tracker_id": sensitive_values[3],
            },
            {
                "arr_library_owned": True,
                "path_key": "another-private-path",
            },
            {
                "transmission_owned": False,
                "arr_library_owned": True,
                "path_key": sensitive_values[1],
                "inode_key": sensitive_values[2],
            },
            {
                "transmission_owned": True,
                "arr_library_owned": False,
                "path_key": "verified-private-payload-path",
                "inode_key": "verified-private-payload-inode",
                "torrent_name": "verified-private-torrent-name",
                "tracker_id": "verified-private-tracker-id",
            },
            {
                "transmission_owned": False,
                "arr_library_owned": True,
                "path_key": "verified-private-library-path",
                "inode_key": "verified-private-library-inode",
            },
        ]

        report = policy.build_legacy_library_inventory_report(records)
        serialized = json.dumps(report, sort_keys=True)

        self.assertEqual(
            report["counts"],
            {
                "transmission_only": 1,
                "legacy_arr_only": 1,
                "shared_path_or_inode": 1,
                "unknown_ownership": 2,
            },
        )
        self.assertEqual(
            set(report), {"mode", "records", "counts", "deletable", "reasons"}
        )
        self.assertEqual(
            set(report["counts"]),
            {
                "transmission_only",
                "legacy_arr_only",
                "shared_path_or_inode",
                "unknown_ownership",
            },
        )
        self.assertEqual(
            report["reasons"],
            {
                "ownership_unverified": 2,
                "legacy_arr_only": 1,
                "shared_path_or_inode": 1,
                "transmission_only": 1,
            },
        )
        self.assertEqual(report["deletable"], 0)
        for sensitive in sensitive_values:
            self.assertNotIn(sensitive, serialized)
        self.assertNotIn("torrent_name", serialized)
        self.assertNotIn("tracker_id", serialized)

    def test_legacy_inventory_is_pure_and_does_not_change_files(self):
        import copy

        with tempfile.TemporaryDirectory() as temporary_directory:
            payload = Path(temporary_directory) / "must-remain-unchanged.bin"
            payload.write_bytes(b"report-only fixture")
            before = payload.read_bytes()
            records = [
                {
                    "transmission_owned": False,
                    "arr_library_owned": True,
                    "path_key": str(payload),
                    "inode_key": "fixture-inode",
                }
            ]
            original = copy.deepcopy(records)

            with patch("builtins.open", side_effect=AssertionError("file access")):
                with patch.object(
                    policy.os, "stat", side_effect=AssertionError("filesystem scan")
                ):
                    with patch.object(
                        policy.os, "scandir", side_effect=AssertionError("filesystem scan")
                    ):
                        with patch.object(
                            policy.Path,
                            "unlink",
                            side_effect=AssertionError("file mutation"),
                        ):
                            report = policy.build_legacy_library_inventory_report(records)

            self.assertEqual(records, original)
            self.assertEqual(payload.read_bytes(), before)
            self.assertTrue(payload.exists())
            self.assertEqual(report["deletable"], 0)
            self.assertNotIn(str(payload), json.dumps(report))

    def test_apply_cli_with_empty_queue_still_emits_remote_disk_usage(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            queue_root = Path(temporary_directory) / "cleanup-queue"
            queue_root.mkdir()
            metrics_path = Path(temporary_directory) / "seedbox.prom"
            output = io.StringIO()
            with patch.object(
                policy,
                "_probe_remote_disk_usage_from_runtime",
                return_value={"used_bytes": 4_000_000_000_000},
                create=True,
            ):
                with redirect_stdout(output):
                    status = policy.main([
                        "--apply",
                        "--queue-root", str(queue_root),
                        "--rpc-url", "/secret/rpc-url",
                        "--download-root", "/secret/download-root",
                        "--ssh-host", "/secret/ssh-host",
                        "--ssh-username", "/secret/ssh-username",
                        "--known-hosts", "/secret/known-hosts",
                        "--ssh-key", "/secret/ssh-key",
                        "--rpc-username", "/secret/rpc-username",
                        "--rpc-password", "/secret/rpc-password",
                        "--ssh", "fake-ssh",
                        "--ssh-keygen", "fake-ssh-keygen",
                        "--remote-disk-capacity-bytes", "4000000000000",
                        "--remote-disk-warning-threshold-bytes", "3000000000000",
                        "--remote-disk-metrics-path", str(metrics_path),
                        "--remote-disk-monitoring",
                    ])

            events = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual(status, 0, output.getvalue())
            self.assertEqual(events[0]["event"], "remote_disk_usage")
            self.assertEqual(events[0]["remote_disk_used_bytes"], 4_000_000_000_000)
            self.assertEqual(events[0]["remote_disk_capacity_bytes"], 4_000_000_000_000)
            self.assertTrue(metrics_path.is_file())

    def test_apply_cli_records_unavailable_disk_probe_without_failing_empty_queue(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            queue_root = Path(temporary_directory) / "cleanup-queue"
            queue_root.mkdir()
            metrics_path = Path(temporary_directory) / "seedbox.prom"
            output = io.StringIO()
            with patch.object(policy, "_probe_remote_disk_usage_from_runtime", return_value=None):
                with redirect_stdout(output):
                    status = policy.main([
                        "--apply",
                        "--queue-root", str(queue_root),
                        "--rpc-url", "/secret/rpc-url",
                        "--download-root", "/secret/download-root",
                        "--ssh-host", "/secret/ssh-host",
                        "--ssh-username", "/secret/ssh-username",
                        "--known-hosts", "/secret/known-hosts",
                        "--ssh-key", "/secret/ssh-key",
                        "--rpc-username", "/secret/rpc-username",
                        "--rpc-password", "/secret/rpc-password",
                        "--ssh", "fake-ssh",
                        "--ssh-keygen", "fake-ssh-keygen",
                        "--remote-disk-capacity-bytes", "4000000000000",
                        "--remote-disk-warning-threshold-bytes", "3000000000000",
                        "--remote-disk-metrics-path", str(metrics_path),
                        "--remote-disk-monitoring",
                    ])

            event = json.loads(output.getvalue().splitlines()[0])
            self.assertEqual(status, 0)
            self.assertEqual(event["event"], "remote_disk_usage_unavailable")
            self.assertFalse(event["remote_disk_probe_success"])
            self.assertIn("ultra_seedbox_storage_probe_success 0", metrics_path.read_text())
            self.assertNotIn("private", output.getvalue())

    def test_runtime_report_keeps_legacy_inventory_unverified_without_data(self):
        self.assertEqual(policy._runtime_unverified_report()["legacy_inventory_status"], "unverified")

    def test_runtime_report_is_aggregate_and_explicitly_unverified(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = io.StringIO()
            with patch.object(policy, "STAGING_ROOT", temporary_directory):
                with redirect_stdout(output):
                    status = policy.main([])
        self.assertEqual(status, 0)
        report = json.loads(output.getvalue().removeprefix("cleanup "))
        self.assertEqual(report["event"], "cleanup_queue_summary")
        self.assertEqual(report["mode"], "report-only")
        self.assertEqual(report["staged_copy_status"], "unverified")
        self.assertEqual(report["legacy_inventory_status"], "unverified")
        self.assertEqual(report["source_ownership_status"], "unverified")
        self.assertEqual(report["runtime_configuration_status"], "unverified")
        self.assertEqual(report["transmission_state"], "unverified")
        self.assertIn("runtime_configuration_unavailable", report["reasons"])
        self.assertIn("source_ownership_unverified", report["reasons"])
        self.assertEqual(report["eligible"], 0)
        self.assertNotIn("path", report)
        self.assertNotIn("secret", output.getvalue().lower())

    def test_report_only_default_never_changes_payload_files(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            payload = Path(temporary_directory) / "legacy-library-copy.bin"
            payload.write_bytes(b"retain this report-only inventory")
            before = payload.read_bytes()
            output = io.StringIO()
            stage_root = Path(temporary_directory) / "stage"
            stage_root.mkdir()
            with patch.object(policy, "STAGING_ROOT", str(stage_root)):
                with redirect_stdout(output):
                    status = policy.main([])
            self.assertEqual(status, 0)
            self.assertTrue(payload.exists())
            self.assertEqual(payload.read_bytes(), before)
            self.assertEqual(json.loads(output.getvalue().removeprefix("cleanup "))["mode"], "report-only")

    def test_report_only_policy_does_not_invoke_transmission_removal(self):
        rpc = transmission_rpc.TransmissionRPC(
            "https://rpc.example.test/transmission/rpc",
            username="test-user",
            password="test-password",
        )
        with patch.object(rpc, "remove_torrent") as remove_torrent:
            report = policy.build_cleanup_report(
                True,
                [self.candidate()],
                staged_copy_prover=lambda _candidate: self.verified_staged_copy(
                    "/srv/media/.arr-staging/movie.mkv"
                ),
                staged_file_verifier=self.matching_staged_file,
            )
        self.assertEqual(report["mode"], "report-only")
        remove_torrent.assert_not_called()


class SyncOrchestrationTests(unittest.TestCase):
    def test_sync_cycle_skips_cleanup_when_stage_reports_busy(self):
        sync = load_sync_module()
        cleanup_called = []

        result = sync.run_sync_cycle(
            lambda: {"status": "busy", "staged": 0, "failed": 0},
            lambda: cleanup_called.append(True),
        )

        self.assertEqual(cleanup_called, [])
        self.assertEqual(result["summary"]["run_status"], "busy")

    def test_sync_cycle_stages_then_cleans_and_emits_aggregate_summary(self):
        sync = load_sync_module()
        events = []
        stage_result = {
            "torrents_total": 4,
            "files_total": 7,
            "bytes_total": 4096,
            "staged": 2,
            "failed": 1,
            "files_transferred": 3,
            "files_reused": 4,
            "bytes_transferred": 1024,
            "bytes_reused": 2048,
            "receipts_created": 2,
            "torrent_id": 99,
            "remote_path": "/private/source.mkv",
        }
        cleanup_result = {
            "mode": "apply",
            "candidates": 1,
            "eligible": 1,
            "blocked": 0,
            "removed": 1,
            "queued": 2,
            "pending_after_run": 1,
            "reasons": {},
            "torrent_id": 99,
        }

        def run_stage():
            events.append("stage")
            return stage_result

        def run_cleanup():
            events.append("cleanup")
            return cleanup_result

        result = sync.run_sync_cycle(run_stage, run_cleanup)

        self.assertEqual(events, ["stage", "cleanup"])
        self.assertEqual(result["summary"], {
            "event": "sync_run_summary",
            "staging_status": "partial",
            "cleanup_status": "complete",
            "run_status": "failed",
            "cleanup_mode": "apply",
            "torrents_total": 4,
            "torrents_staged": 2,
            "files_total": 7,
            "bytes_total": 4096,
            "torrents_failed": 1,
            "files_transferred": 3,
            "files_reused": 4,
            "bytes_transferred": 1024,
            "bytes_reused": 2048,
            "receipts_created": 2,
            "cleanup_candidates": 1,
            "cleanup_removed": 1,
            "cleanup_blocked": 0,
            "pending_after_run": 1,
            "cleanup_reasons": {},
        })
        self.assertNotIn("torrent_id", json.dumps(result["summary"]))
        self.assertNotIn("/private/", json.dumps(result["summary"]))

    def test_cleanup_operation_failures_mark_the_combined_run_failed(self):
        sync = load_sync_module()
        stage_result = {
            "staged": 1,
            "failed": 0,
            "files_transferred": 1,
            "files_reused": 0,
            "bytes_transferred": 1024,
            "bytes_reused": 0,
            "receipts_created": 1,
        }
        cleanup_result = {
            "mode": "apply",
            "candidates": 1,
            "eligible": 0,
            "blocked": 1,
            "removed": 0,
            "reasons": {"transmission_remove_failed": 1},
        }

        result = sync.run_sync_cycle(lambda: stage_result, lambda: cleanup_result)

        self.assertEqual(result["summary"]["cleanup_status"], "failed")
        self.assertEqual(result["summary"]["run_status"], "failed")
        self.assertEqual(result["summary"]["cleanup_reasons"], {"transmission_remove_failed": 1})

    def test_policy_blocks_are_reported_without_failing_the_worker(self):
        sync = load_sync_module()
        result = sync.run_sync_cycle(
            lambda: {"staged": 1, "failed": 0},
            lambda: {
                "mode": "apply",
                "candidates": 1,
                "eligible": 0,
                "blocked": 1,
                "removed": 0,
                "reasons": {"below_retention_threshold": 1},
            },
        )

        self.assertEqual(result["summary"]["cleanup_status"], "blocked")
        self.assertEqual(result["summary"]["run_status"], "complete")

    def test_main_returns_failure_when_cleanup_removal_fails(self):
        sync = load_sync_module()
        output = io.StringIO()
        stage_module = SimpleNamespace(
            RUNTIME_ROOT="/run/ultra-media",
            _stage_from_runtime_files=lambda *_args, **_kwargs: {
                "staged": 1,
                "failed": 0,
                "files_transferred": 1,
                "files_reused": 0,
                "bytes_transferred": 1024,
                "bytes_reused": 0,
                "receipts_created": 1,
            },
        )
        cleanup_module = SimpleNamespace(
            run_runtime_cleanup=lambda *_args, **_kwargs: {
                "mode": "apply",
                "candidates": 1,
                "eligible": 0,
                "blocked": 1,
                "removed": 0,
                "reasons": {"transmission_remove_failed": 1},
            }
        )
        with patch.object(
            sync,
            "_load_runtime_module",
            side_effect=lambda name, _filename: (
                stage_module if name == "ultra_media_download_stage" else cleanup_module
            ),
        ):
            with redirect_stdout(output):
                status = sync.main([
                    "--rpc-url", "/run/secrets/rpc-url",
                    "--download-root", "/run/secrets/download-root",
                    "--ssh-host", "/run/secrets/ssh-host",
                    "--ssh-username", "/run/secrets/ssh-username",
                    "--known-hosts", "/run/secrets/known-hosts",
                    "--ssh-key", "/run/secrets/ssh-key",
                    "--rpc-username", "/run/secrets/rpc-username",
                    "--rpc-password", "/run/secrets/rpc-password",
                    "--ssh", "ssh",
                    "--ssh-keygen", "ssh-keygen",
                    "--rsync", "rsync",
                    "--cleanup-enabled",
                ])

        events = [json.loads(line) for line in output.getvalue().splitlines()]
        summary = next(event for event in events if event.get("event") == "sync_run_summary")
        self.assertEqual(status, 1)
        self.assertEqual(summary["cleanup_status"], "failed")
        self.assertEqual(summary["run_status"], "failed")

    def test_sync_cycle_does_not_cleanup_after_fatal_staging_error(self):
        sync = load_sync_module()
        events = []

        def fail_stage():
            events.append("stage")
            raise RuntimeError("safe staging failure")

        def cleanup():
            events.append("cleanup")
            return {"removed": 0}

        with self.assertRaisesRegex(RuntimeError, "safe staging failure"):
            sync.run_sync_cycle(fail_stage, cleanup)
        self.assertEqual(events, ["stage"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
