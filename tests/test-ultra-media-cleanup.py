"""Synthetic tests for the Ultra.cc retention policy evaluator."""

import importlib.util
import io
import json
import sys
import tempfile
import threading
import time
import unittest
from contextlib import nullcontext, redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import urlsplit


POLICY_PATH = Path(sys.argv.pop(1))
ADAPTER_PATH = Path(sys.argv.pop(1))
STAGING_PATH = Path(sys.argv.pop(1))
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
            "seeding_seconds": 0,
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

    def test_qualifies_at_exact_seeding_time_with_low_ratio(self):
        decision = policy.evaluate_retention(
            self.candidate(seeding_seconds=240 * 60 * 60, torrent_ratio=0.1)
        )
        self.assertTrue(decision["eligible"])

    def test_qualifies_at_exact_torrent_ratio_with_low_seeding_time(self):
        decision = policy.evaluate_retention(
            self.candidate(seeding_seconds=1, torrent_ratio=3.0)
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
        decision = policy.evaluate_retention(
            self.candidate(seeding_seconds=240 * 60 * 60 - 1, torrent_ratio=2.99)
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
    def test_arr_import_proof_requires_source_size_and_local_path_for_every_file(self):
        candidate = {
            "files": [
                {
                    "remote_path": "/seedbox/complete/episode.mkv",
                    "staged_path": "/srv/media/.arr-staging/episode.mkv",
                    "local_path": "/srv/media/shows/episode.mkv",
                    "expected_size": 1024,
                }
            ]
        }
        source_stat = lambda _path: {
            "regular_file": True,
            "size": 1024,
            "mtime_ns": 1_700_000_000_000_000_000,
        }
        proof = policy.make_arr_import_prover(source_stat)(candidate)
        self.assertEqual(proof.status, "verified")
        self.assertEqual(proof.imported_paths, frozenset({"/srv/media/shows/episode.mkv"}))
        self.assertEqual(candidate["files"][0]["expected_mtime_ns"], 1_700_000_000_000_000_000)

    def test_arr_import_proof_fails_closed_when_source_stat_size_changed(self):
        candidate = {
            "files": [
                {
                    "remote_path": "/seedbox/complete/episode.mkv",
                    "staged_path": "/srv/media/.arr-staging/episode.mkv",
                    "local_path": "/srv/media/shows/episode.mkv",
                    "expected_size": 1024,
                }
            ]
        }
        proof = policy.make_arr_import_prover(
            lambda _path: {"regular_file": True, "size": 1023, "mtime_ns": 17}
        )(candidate)
        self.assertEqual(proof.status, "unverified")

    def test_import_history_maps_only_supported_import_events_within_library_roots(self):
        records = [
            {
                "eventType": "downloadFolderImported",
                "data": {
                    "droppedPath": "/srv/media/.arr-staging/episode.mkv",
                    "importedPath": "/srv/media/shows/series/episode.mkv",
                },
            },
            {
                "eventType": "grabbed",
                "data": {
                    "droppedPath": "/srv/media/.arr-staging/ignored.mkv",
                    "importedPath": "/srv/media/shows/ignored.mkv",
                },
            },
            {
                "eventType": "trackFileImported",
                "data": {
                    "droppedPath": "/srv/media/.arr-staging/music.flac",
                    "importedPath": "/srv/media/music/artist/album/music.flac",
                },
            },
        ]
        imported = policy.build_import_path_map(
            records,
            ["/srv/media/shows", "/srv/media/music"],
        )
        self.assertEqual(
            imported,
            {
                "/srv/media/.arr-staging/episode.mkv": "/srv/media/shows/series/episode.mkv",
                "/srv/media/.arr-staging/music.flac": "/srv/media/music/artist/album/music.flac",
            },
        )

    def test_cleanup_candidates_require_unambiguous_mapping_and_carry_safe_metadata(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            stage_root = str(Path(temporary_directory) / ".arr-staging")
            staged_path = str(Path(stage_root) / "Series" / "episode.mkv")
            torrent = {
                "id": 17,
                "candidate": {
                    "complete": True,
                    "seeding_seconds": 864000,
                    "torrent_ratio": 1.5,
                    "trackers": [{"classification": "public"}],
                    "files": [{}],
                },
                "download_directory": "/seedbox/complete",
                "file_paths": ["Series/episode.mkv"],
                "file_paths_valid": True,
                "file_sizes": [1024],
                "file_sizes_valid": True,
            }
            candidates = policy.build_cleanup_candidates(
                [torrent],
                [{"remoteRoot": "/seedbox/complete", "stagingSubpath": ""}],
                {staged_path: "/srv/media/shows/Series/episode.mkv"},
                staging_root=stage_root,
                path_mapper=staging.map_remote_path_to_staging,
            )
        self.assertEqual(len(candidates), 1)
        candidate = candidates[0]
        self.assertEqual(candidate["torrent_id"], 17)
        self.assertEqual(candidate["files"][0]["local_path"], "/srv/media/shows/Series/episode.mkv")
        self.assertEqual(candidate["files"][0]["staged_path"], staged_path)
        self.assertEqual(candidate["files"][0]["remote_path"], "/seedbox/complete/Series/episode.mkv")
        self.assertEqual(candidate["files"][0]["expected_size"], 1024)
        self.assertTrue(candidate["files"][0]["source_mapping_verified"])
        self.assertTrue(candidate["files"][0]["source_ownership_verified"])

    def test_arr_history_fetch_reads_all_pages_with_runtime_api_key_header(self):
        first = {
            "eventType": "downloadFolderImported",
            "data": {
                "droppedPath": "/srv/media/.arr-staging/episode-1.mkv",
                "importedPath": "/srv/media/shows/episode-1.mkv",
            },
        }
        second = {
            "eventType": "downloadFolderImported",
            "data": {
                "droppedPath": "/srv/media/.arr-staging/episode-2.mkv",
                "importedPath": "/srv/media/shows/episode-2.mkv",
            },
        }
        pages = [
            {"records": [first], "totalRecords": 2},
            {"records": [second], "totalRecords": 2},
        ]
        requests = []

        def fake_urlopen(request, timeout):
            requests.append(request)
            return FakeRPCResponse(json.dumps(pages[len(requests) - 1]).encode())

        with tempfile.TemporaryDirectory() as temporary_directory:
            api_key_path = Path(temporary_directory) / "api-key"
            api_key_path.write_text("runtime-api-key")
            with patch.object(policy, "urlopen", side_effect=fake_urlopen):
                imported = policy.fetch_arr_import_paths(
                    [
                        {
                            "baseUrl": "http://127.0.0.1:7878/api/v3",
                            "apiKeyFile": str(api_key_path),
                        }
                    ],
                    ["/srv/media/shows"],
                    page_size=1,
                )

        self.assertEqual(len(requests), 2)
        self.assertTrue(all("apikey=" not in request.full_url.lower() for request in requests))
        self.assertTrue(all(request.get_header("X-api-key") == "runtime-api-key" for request in requests))
        self.assertEqual(len(imported), 2)

    def test_arr_history_fetch_rejects_malformed_records(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            api_key_path = Path(temporary_directory) / "api-key"
            api_key_path.write_text("runtime-api-key")
            response = FakeRPCResponse(
                json.dumps({"records": [None], "totalRecords": 1}).encode()
            )
            with patch.object(policy, "urlopen", return_value=response):
                with self.assertRaises(RuntimeError):
                    policy.fetch_arr_import_paths(
                        [
                            {
                                "baseUrl": "http://127.0.0.1:7878/api/v3",
                                "apiKeyFile": str(api_key_path),
                            }
                        ],
                        ["/srv/media/shows"],
                    )

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

    def test_runtime_apply_keeps_verified_local_import_and_removes_seedbox_copy_via_rpc(self):
        import os

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            stage_root = root / ".arr-staging"
            library_root = root / "library"
            stage_root.mkdir()
            library_root.mkdir()
            local_file = library_root / "episode.mkv"
            local_file.write_bytes(b"payload")
            os.utime(local_file, ns=(1_700_000_000_000_000_000,) * 2)
            staged_path = str(stage_root / "episode.mkv")
            local_path = str(local_file)
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
            arr_config = root / "arr-config.json"
            arr_config.write_text(
                json.dumps(
                    {
                        "libraryRoots": [str(library_root)],
                        "arrApis": [
                            {
                                "baseUrl": "http://127.0.0.1:7878/api/v3",
                                "apiKeyFile": str(root / "api-key"),
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            torrent = {
                "id": 17,
                "candidate": {
                    "complete": True,
                    "seeding_seconds": 240 * 60 * 60,
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
                with patch.object(
                    policy,
                    "fetch_arr_import_paths",
                    return_value={staged_path: local_path},
                ):
                    report = policy.run_runtime_cleanup(
                        secret_paths,
                        str(ssh_key),
                        str(arr_config),
                        ssh_executable="fake-ssh",
                        ssh_keygen_executable="fake-ssh-keygen",
                        apply=True,
                        staging_root=str(stage_root),
                        process_runner=process_runner,
                    )
            self.assertEqual(removals, [(17, True)])
            self.assertEqual(report["removed"], 1)
            self.assertTrue(local_file.exists())
            self.assertEqual(local_file.read_bytes(), b"payload")
            self.assertNotIn("episode.mkv", json.dumps(report))

    def test_local_import_verifier_rejects_symlinks_and_paths_outside_library_roots(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / "library"
            root.mkdir()
            payload = root / "episode.mkv"
            payload.write_bytes(b"fixture")
            alias = root / "alias.mkv"
            alias.symlink_to(payload)
            outside = Path(temporary_directory) / "outside.mkv"
            outside.write_bytes(b"outside")
            self.assertIsNone(
                policy.verify_local_imported_file({"local_path": str(alias)}, [str(root)])
            )
            self.assertIsNone(
                policy.verify_local_imported_file({"local_path": str(outside)}, [str(root)])
            )
            observed = policy.verify_local_imported_file(
                {"local_path": str(payload)}, [str(root)]
            )
        self.assertTrue(observed["regular_file"])
        self.assertEqual(observed["size"], 7)

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

    def test_import_from_stage_into_unapproved_root_fails_closed(self):
        record = {
            "eventType": "downloadFolderImported",
            "data": {
                "droppedPath": "/srv/media/.arr-staging/outside.mkv",
                "importedPath": "/tmp/outside.mkv",
            },
        }
        with self.assertRaises(ValueError):
            policy.build_import_path_map([record], ["/srv/media/shows"])

    def test_malformed_supported_import_history_fails_closed(self):
        with self.assertRaises(ValueError):
            policy.build_import_path_map(
                [{"eventType": "downloadFolderImported", "data": None}],
                ["/srv/media/shows"],
            )

    def test_duplicate_import_destinations_are_not_accepted(self):
        records = [
            {
                "eventType": "downloadFolderImported",
                "data": {
                    "droppedPath": "/srv/media/.arr-staging/first.mkv",
                    "importedPath": "/srv/media/shows/episode.mkv",
                },
            },
            {
                "eventType": "downloadFolderImported",
                "data": {
                    "droppedPath": "/srv/media/.arr-staging/second.mkv",
                    "importedPath": "/srv/media/shows/episode.mkv",
                },
            },
        ]
        self.assertEqual(policy.build_import_path_map(records, ["/srv/media/shows"]), {})

    def test_ambiguous_import_history_does_not_prove_a_local_import(self):
        records = [
            {
                "eventType": "downloadFolderImported",
                "data": {
                    "droppedPath": "/srv/media/.arr-staging/episode.mkv",
                    "importedPath": "/srv/media/shows/first/episode.mkv",
                },
            },
            {
                "eventType": "downloadFolderImported",
                "data": {
                    "droppedPath": "/srv/media/.arr-staging/episode.mkv",
                    "importedPath": "/srv/media/shows/second/episode.mkv",
                },
            },
        ]
        imported = policy.build_import_path_map(records, ["/srv/media/shows"])
        self.assertEqual(imported, {})


class CleanupExecutionTests(unittest.TestCase):
    def candidate(self):
        return {
            "torrent_id": 17,
            "complete": True,
            "seeding_seconds": 240 * 60 * 60,
            "torrent_ratio": 0.2,
            "runtime_config_available": True,
            "rpc_available": True,
            "arr_state_available": True,
            "trackers": [{"classification": "public"}],
            "files": [
                {
                    "mapped": True,
                    "source_mapping_verified": True,
                    "source_identity": "source-path-17",
                    "source_ownership_verified": True,
                    "source_owner_count": 1,
                    "local_path": "/library/movie.mkv",
                    "expected_size": 1024,
                    "expected_mtime_ns": 1_700_000_000_000_000_000,
                }
            ],
        }

    def proof(self, _candidate):
        return policy.ArrImportProof.verified(["/library/movie.mkv"])

    def local_file(self, _file):
        return {
            "regular_file": True,
            "size": 1024,
            "mtime_ns": 1_700_000_000_000_000_000,
        }

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
            arr_import_prover=self.proof,
            local_file_verifier=self.local_file,
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
            arr_import_prover=self.proof,
            local_file_verifier=self.local_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: False,
        )
        self.assertEqual(removals, [])
        self.assertEqual(report["removed"], 0)
        self.assertEqual(report["reasons"], {"torrent_revalidation_failed": 1})

    def test_apply_blocks_candidates_that_share_an_imported_local_path(self):
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
            arr_import_prover=self.proof,
            local_file_verifier=self.local_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: True,
        )
        self.assertEqual(removals, [])
        self.assertEqual(report["removed"], 0)
        self.assertEqual(report["reasons"], {"shared_file_unsafe": 2})

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
            arr_import_prover=self.proof,
            local_file_verifier=self.local_file,
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
            arr_import_prover=self.proof,
            local_file_verifier=self.local_file,
            transmission_rpc=rpc,
            apply=True,
            revalidate_candidate=lambda _candidate: True,
        )
        self.assertEqual(removals, [])
        self.assertEqual(report["removed"], 0)
        self.assertEqual(report["reasons"], {"staging_not_successful": 1})


class DownloadStagingTests(unittest.TestCase):
    def test_stage_success_marker_is_cleared_before_run_and_written_after_success(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            marker = Path(temporary_directory) / "stage-success.json"
            marker.write_text("stale token", encoding="utf-8")
            staging.clear_stage_success_marker(str(marker))
            self.assertFalse(marker.exists())

            staging.write_stage_success_marker(str(marker), monotonic_ns=123456789)
            self.assertEqual(
                json.loads(marker.read_text(encoding="utf-8")),
                {"monotonic_ns": 123456789},
            )

    def test_stage_success_marker_write_uses_private_regular_file(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            marker = Path(temporary_directory) / "stage-success.json"
            staging.write_stage_success_marker(str(marker), monotonic_ns=123456789)
            self.assertTrue(marker.is_file())
            self.assertEqual(marker.stat().st_mode & 0o777, 0o660)

    def test_stage_main_creates_marker_only_after_a_successful_copy_run(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            marker = Path(temporary_directory) / "stage-success.json"
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
                "--success-marker", str(marker),
            ]
            output = io.StringIO()
            with patch.object(staging, "_operation_lock", return_value=nullcontext()):
                with patch.object(
                    staging,
                    "_stage_from_runtime_files",
                    return_value={"completed_candidates": 1, "staged": 1, "skipped_incomplete": 0, "skipped_unknown_path": 0, "skipped_malformed_path": 0, "failed": 0},
                ):
                    with redirect_stdout(output):
                        status = staging.main(arguments)
            self.assertEqual(status, 0)
            self.assertTrue(marker.is_file())

            with patch.object(staging, "_operation_lock", return_value=nullcontext()):
                with patch.object(
                    staging,
                    "_stage_from_runtime_files",
                    return_value={"completed_candidates": 1, "staged": 0, "skipped_incomplete": 0, "skipped_unknown_path": 0, "skipped_malformed_path": 0, "failed": 1},
                ):
                    with redirect_stdout(io.StringIO()):
                        status = staging.main(arguments)
            self.assertEqual(status, 1)
            self.assertFalse(marker.exists())

    def setUp(self):
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
        return {
            "candidate": {"complete": complete},
            "download_directory": download_directory,
            "file_paths": file_paths,
            "file_paths_valid": True,
        }

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

            def transfer(remote_source, temporary_file):
                transfers.append(remote_source)
                temporary_file.write_bytes(b"complete payload")

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
                    "skipped_incomplete": 1,
                    "skipped_unknown_path": 1,
                    "skipped_malformed_path": 1,
                    "failed": 0,
                },
            )

    def test_partial_transfer_is_not_published_or_counted_complete(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / ".arr-staging"

            def partial_transfer(_remote_source, temporary_file):
                temporary_file.write_bytes(b"partial")
                raise OSError("synthetic transfer failure")

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
            )
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
            key_path.write_text("test key", encoding="utf-8")
            secret_paths = self.write_runtime_secrets(root, server.url)
            Path(secret_paths["download_root"]).write_text(
                "/seedbox/complete", encoding="utf-8"
            )
            transfer_commands = []

            def mocked_process_runner(arguments, **_kwargs):
                if arguments[0] == "fake-ssh-keygen":
                    return SimpleNamespace(returncode=0)
                if arguments[0] == "fake-rsync":
                    transfer_commands.append(arguments)
                    Path(arguments[-1]).write_bytes(b"local fixture payload")
                    return SimpleNamespace(returncode=0)
                self.fail("staging invoked an unexpected local process")

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
                        staging_root=staging_root,
                    )
            finally:
                if old_adapter is None:
                    sys.modules.pop("transmission_rpc", None)
                else:
                    sys.modules["transmission_rpc"] = old_adapter
                server.close()

            self.assertEqual(result["staged"], 1)
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
            "seeding_seconds": 240 * 60 * 60,
            "torrent_ratio": 3.0,
            "runtime_config_available": True,
            "rpc_available": True,
            "arr_state_available": True,
            "trackers": [{"classification": "public"}],
            "files": [
                {
                    "mapped": True,
                    "source_mapping_verified": True,
                    "source_identity": f"fixture-source-{self._source_counter}",
                    "source_ownership_verified": True,
                    "source_owner_count": 1,
                    "local_path": "/library/movie.mkv",
                    "expected_size": 1024,
                    "expected_mtime_ns": 1_700_000_000_000_000_000,
                }
            ],
        }
        value.update(overrides)
        return value

    def verified_import(self, *paths):
        return policy.ArrImportProof.verified(paths)

    def matching_local_file(self, _file):
        return {
            "regular_file": True,
            "size": 1024,
            "mtime_ns": 1_700_000_000_000_000_000,
        }

    def test_cleanup_skips_remote_import_and_file_proofs_below_retention_limits(self):
        calls = []
        candidate = self.candidate(seeding_seconds=1, torrent_ratio=2.99)
        report = policy.build_cleanup_report(
            True,
            [candidate],
            arr_import_prover=lambda _candidate: calls.append("arr"),
            local_file_verifier=lambda _file: calls.append("local"),
        )
        self.assertEqual(calls, [])
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"below_retention_threshold": 1})

    def test_cleanup_verifies_only_after_successful_staging_and_import(self):
        events = ["stage-succeeded"]
        candidate = self.candidate()

        def prove_import(_candidate):
            events.append("arr-import-proof")
            return self.verified_import("/library/movie.mkv")

        def verify_file(file_record):
            events.append("local-size-mtime-proof")
            return self.matching_local_file(file_record)

        report = policy.build_cleanup_report(
            True,
            [candidate],
            arr_import_prover=prove_import,
            local_file_verifier=verify_file,
        )

        self.assertEqual(
            events,
            ["stage-succeeded", "arr-import-proof", "local-size-mtime-proof"],
        )
        self.assertEqual(report["mode"], "report-only")
        self.assertEqual(report["eligible"], 1)

    def test_failed_staging_prevents_import_and_local_verification(self):
        calls = []
        report = policy.build_cleanup_report(
            False,
            [self.candidate()],
            arr_import_prover=lambda _candidate: calls.append("arr"),
            local_file_verifier=lambda _file: calls.append("local"),
        )
        self.assertEqual(calls, [])
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"staging_not_successful": 1})

    def test_missing_runtime_config_blocks_before_import_or_file_verification(self):
        calls = []
        candidate = self.candidate(runtime_config_available=False)
        report = policy.build_cleanup_report(
            True,
            [candidate],
            arr_import_prover=lambda _candidate: calls.append("arr"),
            local_file_verifier=lambda _file: calls.append("local"),
        )
        self.assertEqual(calls, [])
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"runtime_configuration_unavailable": 1})

    def test_unavailable_transmission_or_arr_state_fails_closed(self):
        missing_rpc = self.candidate()
        missing_rpc.pop("rpc_available")
        for status_name, status in (
            ("transmission_state_unavailable", {"rpc_available": False, "arr_state_available": True}),
            ("transmission_state_unavailable", {"candidate": missing_rpc}),
            ("arr_state_unavailable", {"rpc_available": True, "arr_state_available": False}),
        ):
            with self.subTest(status=status):
                calls = []
                candidate = status.pop("candidate") if "candidate" in status else self.candidate(**status)
                report = policy.build_cleanup_report(
                    True,
                    [candidate],
                    arr_import_prover=lambda _candidate: calls.append("arr"),
                    local_file_verifier=lambda _file: calls.append("local"),
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
                    arr_import_prover=lambda _candidate: calls.append("arr"),
                    local_file_verifier=lambda _file: calls.append("local"),
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
            arr_import_prover=lambda _candidate: calls.append("arr"),
            local_file_verifier=lambda _file: calls.append("local"),
        )
        self.assertEqual(calls, [])
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"source_ownership_unverified": 1})

    def test_arr_import_proof_is_required_and_unverified_fails_closed(self):
        report = policy.build_cleanup_report(
            True,
            [self.candidate()],
            arr_import_prover=lambda _candidate: policy.ArrImportProof.unverified(),
            local_file_verifier=self.matching_local_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"arr_import_unverified": 1})

    def test_arr_import_proof_must_cover_every_payload_file(self):
        report = policy.build_cleanup_report(
            True,
            [self.candidate()],
            arr_import_prover=lambda _candidate: self.verified_import(
                "/library/another-file.mkv"
            ),
            local_file_verifier=self.matching_local_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"arr_import_unverified": 1})

    def test_local_size_and_mtime_must_both_match(self):
        candidate = self.candidate()
        for observed in (
            {
                "regular_file": True,
                "size": 1023,
                "mtime_ns": 1_700_000_000_000_000_000,
            },
            {
                "regular_file": True,
                "size": 1024,
                "mtime_ns": 1_700_000_000_000_000_001,
            },
        ):
            with self.subTest(observed=observed):
                report = policy.build_cleanup_report(
                    True,
                    [candidate],
                    arr_import_prover=lambda _candidate: self.verified_import(
                        "/library/movie.mkv"
                    ),
                    local_file_verifier=lambda _file: observed,
                )
                self.assertEqual(report["eligible"], 0)
                self.assertEqual(report["reasons"], {"local_file_mismatch": 1})

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
            arr_import_prover=lambda _candidate: self.verified_import(
                "/library/movie.mkv"
            ),
            local_file_verifier=self.matching_local_file,
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
            arr_import_prover=lambda _candidate: self.verified_import(
                "/library/movie.mkv"
            ),
            local_file_verifier=self.matching_local_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"private_ratio_below_floor": 1})

    def test_unknown_tracker_blocks_cleanup_report(self):
        candidate = self.candidate(trackers=[{"classification": "unknown"}])
        report = policy.build_cleanup_report(
            True,
            [candidate],
            arr_import_prover=lambda _candidate: self.verified_import(
                "/library/movie.mkv"
            ),
            local_file_verifier=self.matching_local_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"tracker_classification_unknown": 1})

    def test_overlapping_local_paths_block_every_candidate_sharing_the_path(self):
        first = self.candidate()
        second = self.candidate()
        report = policy.build_cleanup_report(
            True,
            [first, second],
            arr_import_prover=lambda _candidate: self.verified_import(
                "/library/movie.mkv"
            ),
            local_file_verifier=self.matching_local_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"shared_file_unsafe": 2})

    def test_different_local_paths_sharing_one_source_inode_block_cleanup(self):
        first = self.candidate()
        second = self.candidate()
        first["files"][0]["local_path"] = "/library/first.mkv"
        second["files"][0]["local_path"] = "/library/renamed-copy.mkv"
        for candidate in (first, second):
            candidate["files"][0]["source_identity"] = "fixture-same-inode"
            candidate["files"][0]["source_owner_count"] = 2
        report = policy.build_cleanup_report(
            True,
            [first, second],
            arr_import_prover=lambda _candidate: self.verified_import(
                "/library/first.mkv", "/library/renamed-copy.mkv"
            ),
            local_file_verifier=self.matching_local_file,
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(report["reasons"], {"source_file_shared": 2})

    def test_stage_and_cleanup_runs_share_one_exclusive_operation_lock(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / ".arr-staging"
            entered = threading.Event()
            acquired = threading.Event()

            with policy._operation_lock(root):
                def stage_after_cleanup_lock():
                    entered.set()
                    with staging._operation_lock(root):
                        acquired.set()

                worker = threading.Thread(target=stage_after_cleanup_lock)
                worker.start()
                self.assertTrue(entered.wait(timeout=1))
                time.sleep(0.05)
                self.assertFalse(acquired.is_set())

            worker.join(timeout=2)
            self.assertFalse(worker.is_alive())
            self.assertTrue(acquired.is_set())

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

    def test_apply_success_signal_is_recent_and_consumed_once(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            marker = Path(temporary_directory) / "stage-success.json"
            marker.write_text(json.dumps({"monotonic_ns": 900}), encoding="utf-8")
            self.assertTrue(
                policy.consume_stage_success_marker(
                    str(marker), now_monotonic_ns=1_000, max_age_seconds=1
                )
            )
            self.assertFalse(marker.exists())
            self.assertFalse(
                policy.consume_stage_success_marker(
                    str(marker), now_monotonic_ns=1_001, max_age_seconds=1
                )
            )

    def test_expired_apply_success_signal_is_rejected_and_removed(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            marker = Path(temporary_directory) / "stage-success.json"
            marker.write_text(json.dumps({"monotonic_ns": 1}), encoding="utf-8")
            self.assertFalse(
                policy.consume_stage_success_marker(
                    str(marker), now_monotonic_ns=2_000_000_000, max_age_seconds=1
                )
            )
            self.assertFalse(marker.exists())

    def test_apply_cli_requires_successful_staging_before_runtime_access(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            stage_root = Path(temporary_directory) / "stage"
            stage_root.mkdir()
            marker = Path(temporary_directory) / "missing-stage-success.json"
            output = io.StringIO()
            with patch.object(policy, "STAGING_ROOT", str(stage_root)):
                with patch.object(policy, "OPERATION_LOCK_PATH", str(Path(temporary_directory) / "lock")):
                    with redirect_stdout(output):
                        status = policy.main(["--apply", "--stage-success-marker", str(marker)])
        self.assertEqual(status, 1)
        self.assertEqual(output.getvalue(), "cleanup failed reason=staging_not_successful\n")

    def test_runtime_report_keeps_legacy_inventory_unverified_without_data(self):
        self.assertEqual(policy._runtime_unverified_report()["legacy_inventory_status"], "unverified")

    def test_runtime_report_is_aggregate_and_explicitly_unverified(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = io.StringIO()
            with patch.object(policy, "STAGING_ROOT", temporary_directory):
                with patch.object(policy, "OPERATION_LOCK_PATH", str(Path(temporary_directory) / "lock")):
                    with redirect_stdout(output):
                        status = policy.main([])
        self.assertEqual(status, 0)
        report = json.loads(output.getvalue().removeprefix("cleanup "))
        self.assertEqual(report["mode"], "report-only")
        self.assertEqual(report["arr_import_status"], "unverified")
        self.assertEqual(report["legacy_inventory_status"], "unverified")
        self.assertEqual(report["source_ownership_status"], "unverified")
        self.assertEqual(report["runtime_configuration_status"], "unverified")
        self.assertEqual(report["transmission_state"], "unverified")
        self.assertEqual(report["arr_state_status"], "unverified")
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
                with patch.object(policy, "OPERATION_LOCK_PATH", str(Path(temporary_directory) / "lock")):
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
                arr_import_prover=lambda _candidate: self.verified_import(
                    "/library/movie.mkv"
                ),
                local_file_verifier=self.matching_local_file,
            )
        self.assertEqual(report["mode"], "report-only")
        remove_torrent.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
